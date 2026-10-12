-- Auction -> recheck -> confirmed purchase -> bag GUID -> observed yield.
-- This module never buys, casts, equips, sells or destroys an item.
local _, ns = ...
local Eco = ns.Economy
local floor, max, min = math.floor, math.max, math.min
local session = { checks = {}, intents = {} }
local EquippedGUIDs
Eco.DEWorkflow = session

local function Store()
 local e = Eco.DB()
 e.deWorkflow = e.deWorkflow or { exclusions={}, terms={}, purchases={}, order={} }
 return e.deWorkflow
end
local function Refresh()
 if Eco.Refresh then Eco.Refresh() end
end
local function Variant(link, id)
 local suffix = Eco.LinkSuffix(link)
 return suffix and (id .. ":" .. suffix) or tostring(id)
end
local function Excluded(id, link, it)
 local db=Store()
 if db.exclusions[tostring(id)] or db.exclusions[Variant(link,id)] then return true end
 local text=(it.name or ""):lower()
 local stats=(C_Item and C_Item.GetItemStats) or GetItemStats
 if stats and link then
  local ok, values=pcall(stats,link)
  if ok and type(values)=="table" then
   for k in pairs(values) do text=text.." "..tostring(_G[k] or k):lower() end
  end
 end
 for _,term in ipairs(db.terms) do if text:find(term,1,true) then return true end end
 return false
end
Eco.DEExcluded=Excluded
function Eco.DEExclude(id, excluded)
 Store().exclusions[tostring(id)]=excluded and true or nil
 session.checks={}; Refresh()
end
function Eco.DESetExclusionTerms(text)
 local terms={}
 for term in tostring(text or ""):gmatch("[^,]+") do
  term=term:match("^%s*(.-)%s*$"):lower()
  if #term>0 then terms[#terms+1]=term end
 end
 Store().terms=terms;session.checks={};Refresh()
end
function Eco.DEGetExclusionTerms() return table.concat(Store().terms,", ") end

-- Current scan only: a missing material price is never silently valued at zero.
function Eco.DECurrentValue(def)
 local _,market=Eco.DB()
 local total, prices, missing=0,{},{}
 for _,mat in ipairs(def.results) do
  local rec=market.items[mat[1]]
  local price=rec and rec.s==market.scanId and rec.m
  if price and price>0 then
   prices[mat[1]]={unit=price,at=rec.t or market.lastScan}
   total=total+mat[2]*(mat[3]+mat[4])/2*price
  else missing[#missing+1]=mat[1] end
 end
 if #missing>0 then return nil,prices,missing end
 return total*(1-Eco.cut),prices,missing
end

local function Evaluate(key,link,price,qty,quick)
 local id=Eco.BaseID(key)
 local it=Eco.Item(link or id)
 if not it or (it.class~=2 and it.class~=4) or it.quality<2 or not price or price<=0 or qty<=0 then return end
 if it.bind==1 then return end
 if Excluded(id,link,it) then return end
 local def=Eco.DE.LotOf(it)
 local state,why,required=Eco.DEState(link or id)
 local rank=Eco.DB().enchanters[ns.CharKey()]
 rank=rank and tonumber(rank.r)
 required=required or (def and def.skill)
 local skillOK=rank and required and rank>=required
 local expected,prices,missing
 if def then expected,prices,missing=Eco.DECurrentValue(def) end
 local vendor=(it.sell or 0)*qty
 local deProfit=expected and expected*qty-price
 local deMargin=deProfit and deProfit/price*100
 local st=Eco.DB().settings
 local vendorOK=vendor>price
 local deOK=def and state~="no" and skillOK and deMargin and deMargin>st.deReturn
 if not vendorOK and not deOK then return end
 if st.deCapital>0 and price>st.deCapital then return end
 local route=(deOK and (not vendorOK or deProfit>vendor-price)) and "de" or "vendor"
 local net=route=="de" and deProfit or vendor-price
 local token=tostring(key)..":"..price..":"..qty
 local check=session.checks[token]
 if check and (check.market~=Eco.market.key or check.scan~=select(2,Eco.DB()).scanId) then check=nil end
 if check and check.auction and time()-(check.at or 0)>60 then check={status="Price check expired; recheck again"} end
 return {key="trade:"..token,token=token,method="de",trade=true,id=id,link=link or it.link,icon=it.icon,
  itemQuality=it.quality,label=it.name..(qty>1 and (" x"..qty) or ""),qty=qty,cost=price,expected=expected and expected*qty,
  net=net,margin=net/price*100,vendor=vendor,route=route,def=def,prices=prices,required=required,rank=rank,
  quality=1,verified=false,eligible=route=="vendor" or (state=="ok" and skillOK),state=state,why=why,
  reasons={"Latest scan prices; auctions may have changed.","Classic yield probabilities, not verified server yields."},
  quick=quick,check=check,d={modelReady=false},variant=Variant(link or it.link,id)}
end
Eco.DEEvaluateAuction=Evaluate

function Eco.DEAuctionRows()
 local _,market=Eco.DB()
 local rows={}
 for key,rec in pairs(market.items) do
  if rec.s==market.scanId and rec.m then
   local full=market.lastMode=="full"
   local exact=full and ((Eco.S.deAuctions and Eco.S.deAuctions[key]) or rec.deAuctions)
   if exact then
    for _,a in ipairs(exact) do
     local row=Evaluate(key,a.link,a.buyout,a.quantity,false)
     if row and row.route=="de" then rows[#rows+1]=row end
    end
   else
   local book=full and (Eco.S.books[key] or rec.b) or nil
   book=book or {rec.m*Eco.PACK+1}
   for _,packed in ipairs(book) do
    local unit,qty=Eco.Unpack(packed)
    local row=Evaluate(key,rec.l,unit*qty,qty,true)
    if row and row.route=="de" then rows[#rows+1]=row end
   end
   end
  end
 end
 -- Identical auctions share a row and a count; a recheck resolves a concrete ID.
 local unique,out={},{}
 for _,row in ipairs(rows) do
  if unique[row.key] then unique[row.key].count=unique[row.key].count+1
  else row.count=1;unique[row.key]=row;out[#out+1]=row end
 end
 table.sort(out,function(a,b) if a.net~=b.net then return a.net>b.net end return a.key<b.key end)
 return out
end

local function Status(row)
 if row.route=="vendor" then return "Vendor resale" end
 if row.state~="ok" then return "Check eligibility" end
 return "DE estimate"
end
Eco.DETradeStatus=Status

-- Serialize the click-time query with the existing scan and the client's throttle.
local function SameKey(a,b)
 return a and b and a.itemID==b.itemID and (a.itemSuffix or 0)==(b.itemSuffix or 0)
  and (a.itemLevel or 0)==(b.itemLevel or 0) and (a.battlePetSpeciesID or 0)==(b.battlePetSpeciesID or 0)
end
local function FinishCheck(job,status,found)
 if session.job~=job then return end
 session.job=nil
 if job.timer then job.timer:Cancel() end
 if Eco.S.state=="decheck" then Eco.S.state="idle" end
 if found then found={auctionID=found.auctionID,itemLink=found.itemLink,buyoutAmount=found.buyoutAmount,quantity=found.quantity} end
 local check={status=status,at=time(),market=Eco.market.key,scan=select(2,Eco.DB()).scanId,auction=found}
 session.checks[job.row.token]=check
 if found then
  session.intents[found.auctionID]={row=job.row,auction=found,at=time(),market=Eco.market.key}
 end
 Refresh();if Eco.UpdateStatus then Eco.UpdateStatus() end
end
local function Send(job,more)
 if session.job~=job then return end
 if not Eco.AuctionHouseOpen() then return FinishCheck(job,"Auction house closed") end
 local ah=C_AuctionHouse
 if ah.IsThrottledMessageSystemReady and not ah.IsThrottledMessageSystemReady() then
  job.sendMore=more;job.waitingThrottle=true;return
 end
 job.waitingThrottle=false;job.awaiting=true
 local ok,err
 if more then ok,err=pcall(ah.RequestMoreItemSearchResults,job.itemKey)
 else ok,err=pcall(ah.SendSearchQuery,job.itemKey,{},true) end
 if not ok then FinishCheck(job,"Search unavailable on this client: "..tostring(err)) end
end
function Eco.DERecheck(row)
 if not row or not row.trade then return end
 if not Eco.AuctionHouseOpen() then ns.Print("Open the auction house to recheck this auction.");return end
 if Eco.S.state~="idle" then ns.Print("Wait for the current scan or search.");return end
 local ah=C_AuctionHouse
 if not (ah and ah.SendSearchQuery and ah.GetNumItemSearchResults and ah.GetItemSearchResultInfo and ah.HasFullItemSearchResults) then
  session.checks[row.token]={status="This client cannot verify exact auctions",market=Eco.market.key,scan=select(2,Eco.DB()).scanId};Refresh();return
 end
 local it=Eco.Item(row.link or row.id)
 local itemKey={itemID=row.id,itemLevel=it and it.level or 0,itemSuffix=Eco.LinkSuffix(row.link) or 0,battlePetSpeciesID=0}
 local job={row=row,itemKey=itemKey,pages=0}
 session.job=job;session.checks[row.token]={status="Checking current auctions...",market=Eco.market.key,scan=select(2,Eco.DB()).scanId}
 Eco.S.state="decheck"
 job.timer=C_Timer.NewTimer(30,function() FinishCheck(job,"Recheck timed out; try again") end)
 Send(job,false);Refresh()
end
local function OnResults(_,key)
 local job=session.job
 if not job or not job.awaiting or not SameKey(key,job.itemKey) then return end
 job.awaiting=false
 local ah=C_AuctionHouse
 for i=1,ah.GetNumItemSearchResults(key) do
  local a=ah.GetItemSearchResultInfo(key,i)
  if a and a.auctionID and a.itemLink and not a.containsOwnerItem and not a.containsAccountItem
   and a.buyoutAmount==job.row.cost and a.quantity==job.row.qty
   and Eco.LinkID(a.itemLink)==job.row.id
   and Variant(a.itemLink,key.itemID)==job.row.variant then
   return FinishCheck(job,"Same buyout confirmed; buy manually at the auction house",a)
  end
 end
 if ah.HasFullItemSearchResults(key) then return FinishCheck(job,"Gone or price changed; scan again") end
 job.pages=job.pages+1
 if job.pages>100 or not ah.RequestMoreItemSearchResults then return FinishCheck(job,"Incomplete results; auction not verified") end
 -- A result event can arrive twice. Only a scheduled request can arm the next read.
 C_Timer.After(1,function() Send(job,true) end)
end
ns.On("ITEM_SEARCH_RESULTS_UPDATED",OnResults)
ns.On("ITEM_SEARCH_RESULTS_ADDED",OnResults)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY",function()
 local job=session.job
 if job and job.waitingThrottle then Send(job,job.sendMore) end
end)
ns.On("AUCTION_HOUSE_CLOSED",function()
 if session.job then FinishCheck(session.job,"Auction house closed") end
 for id,intent in pairs(session.intents) do if not intent.submitted then session.intents[id]=nil end end
 session.checks={}
end)

local function BagItems()
 local out={}
 local c=C_Container
 if not (c and c.GetContainerNumSlots and c.GetContainerItemInfo) then return out end
 for bag=0,4 do
  for slot=1,c.GetContainerNumSlots(bag) do
   local info=c.GetContainerItemInfo(bag,slot)
   if info and info.hyperlink then
    local loc=ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag,slot)
    local guid=loc and C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(loc)
    if guid then out[guid]={guid=guid,bag=bag,slot=slot,link=info.hyperlink,id=Eco.LinkID(info.hyperlink),qty=info.stackCount or 1,locked=info.isLocked} end
   end
  end
 end
 return out
end
Eco.DEBagItems=BagItems
-- Observe only the user's own manual buyout, then require the success event.
local hooked=false
local function HookPurchases()
 if hooked or not (C_AuctionHouse and C_AuctionHouse.PlaceBid and hooksecurefunc) then return end
 hooked=true
 hooksecurefunc(C_AuctionHouse,"PlaceBid",function(id,amount)
  local intent=session.intents[id]
  if intent and intent.market==Eco.market.key and time()-intent.at<=60 and amount==intent.auction.buyoutAmount then
   intent.submitted=true;intent.before=BagItems();intent.at=time()
   for guid in pairs(EquippedGUIDs()) do intent.before[guid]=true end
  end
 end)
end
ns.On("AUCTION_HOUSE_SHOW",HookPurchases)
ns.On("PLAYER_LOGIN",HookPurchases)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED",function(_,id)
 local intent=session.intents[id]
 if not intent or not intent.submitted or time()-intent.at>60 then return end
 session.intents[id]=nil
 local db=Store();local key=intent.market..":"..ns.CharKey()..":"..id
 if db.purchases[key] then return end
 local row=intent.row
 local p={key=key,id=row.id,link=row.link,variant=row.variant,qty=row.qty,left=row.qty,cost=intent.auction.buyoutAmount,
  expected=row.expected,prices=row.prices,route=row.route,at=time(),who=ns.CharKey(),market=intent.market,before={},guids={},outcomes={}}
 for guid in pairs(intent.before or {}) do p.before[guid]=true end
 db.purchases[key]=p;db.order[#db.order+1]=key
 session.checks[row.token]=nil;Refresh()
end)

-- Bag candidates require a confirmed purchase AND explicit marking of the GUID.
-- No item equipped before or after the purchase is ever offered.
EquippedGUIDs=function()
 local set={}
 if ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemGUID then
  for slot=1,19 do
   local loc=ItemLocation:CreateFromEquipmentSlot(slot)
   local ok,guid=pcall(C_Item.GetItemGUID,loc)
   if ok and guid then set[guid]=true end
  end
 end
 return set
end
local function ProtectEquipment()
 local db=Store();db.equipment=db.equipment or {};local key=ns.CharKey()
 db.equipment[key]=db.equipment[key] or {}
 for guid in pairs(EquippedGUIDs()) do db.equipment[key][guid]=true end
 return db.equipment[key]
end
function Eco.DEBagRows()
 local db=Store();local rows={};local equipped=ProtectEquipment()
 for _,key in ipairs(db.order) do
  local p=db.purchases[key]
  if p.who==ns.CharKey() and p.route=="de" and p.left>0 then
   p.protected=p.protected or {}
   for guid in pairs(equipped) do p.protected[guid]=true end
  end
 end
 for guid,b in pairs(BagItems()) do
  local matches={}
  for _,key in ipairs(db.order) do
   local p=db.purchases[key]
   if not b.locked and p.who==ns.CharKey() and p.route=="de" and p.left>0 and p.id==b.id and p.variant==Variant(b.link,b.id)
    and not p.before[guid] and not (p.protected and p.protected[guid]) and not equipped[guid] then matches[#matches+1]=p end
  end
  if #matches>0 then
   local p=matches[1]
   for _,candidate in ipairs(matches) do if candidate.guids[guid] then p=candidate;break end end
   local it=Eco.Item(b.link)
   local state=Eco.DEState(b.link)
   local def=it and Eco.DE.LotOf(it)
   local rank=Eco.DB().enchanters[ns.CharKey()]
   if it and def and b.qty<=p.left and not Excluded(b.id,b.link,it) and state~="no" and rank and rank.r and rank.r>=def.skill then
    rows[#rows+1]={key="bag:"..guid,method="de",bagItem=true,id=b.id,link=b.link,label=it.name,icon=it.icon,
     itemQuality=it.quality,quality=0,verified=false,eligible=false,reasons={},why="Confirm this is the purchased item before disenchanting manually.",
     d={modelReady=false},bag=b,purchase=p,marked=p.guids[guid]==true,cost=p.cost/p.qty}
   end
  end
 end
 table.sort(rows,function(a,b)return a.key<b.key end)
 return rows
end
function Eco.DEMarkBag(row)
 for _,current in ipairs(Eco.DEBagRows()) do
  if current.key==row.key then
   local marked=0
   for _ in pairs(current.purchase.guids) do marked=marked+1 end
   if not current.marked and marked>=current.purchase.left then return false end
   current.purchase.guids[row.bag.guid]=true;Refresh();return true
  end
 end
 return false
end
ns.On("PLAYER_EQUIPMENT_CHANGED",function() Eco.DEBagRows() end)
ns.On("PLAYER_LOGIN",ProtectEquipment)
ns.On("BAG_UPDATE_DELAYED",function()
 if Eco.frame and Eco.frame:IsShown() then Refresh() end
end)

function Eco.DERecordYield(link,guid,mats)
 if not guid then return end
 local db=Store()
 for _,key in ipairs(db.order) do
  local p=db.purchases[key]
  if p.who==ns.CharKey() and p.left>0 and p.guids[guid] and p.variant==Variant(link,Eco.LinkID(link)) then
   p.guids[guid]=nil;p.left=p.left-1
   local value=0;local missing=false;local _,market=Eco.DB()
   for id,qty in pairs(mats) do
    local rec=market.items[id]
    if rec and rec.m and rec.s==market.scanId then value=value+qty*rec.m*(1-Eco.cut) else missing=true end
   end
   p.outcomes[#p.outcomes+1]={at=time(),guid=guid,mats=mats,value=not missing and value or nil,scan=market.lastScan}
   Refresh();return
  end
 end
end

function Eco.DEJournalRows()
 local rows={};local db=Store()
 for _,key in ipairs(db.order) do
  local p=db.purchases[key]
  if p.who==ns.CharKey() and p.market==Eco.market.key then
   local it=Eco.Item(p.link or p.id);local value,complete=0,true
   for _,o in ipairs(p.outcomes) do if o.value then value=value+o.value else complete=false end end
   rows[#rows+1]={key="journal:"..key,method="de",journal=true,purchase=p,id=p.id,link=p.link,label=it and it.name or tostring(p.id),
    icon=it and it.icon,itemQuality=it and it.quality,cost=p.cost,expected=p.expected,quality=0,verified=false,eligible=false,
    why="Generated loot is recorded, not confirmed bag receipt. Its valuation is not a realized sale.",reasons={},d={modelReady=false},
    observed=complete and #p.outcomes>0 and value or nil,net=p.sale and p.sale.net-p.cost-p.sale.loss or nil}
  end
 end
 table.sort(rows,function(a,b)return a.purchase.at>b.purchase.at end)
 return rows
end
function Eco.DERecordSale(row,netGold,lostGold)
 local p=row and row.purchase
 if not p or p.who~=ns.CharKey() then return false end
 local net,loss=tonumber(netGold),tonumber(lostGold)
 if not net or not loss or net<0 or loss<0 or net>1e9 or loss>1e9 then return false end
 p.sale={net=floor(net*10000+0.5),loss=floor(loss*10000+0.5),at=time(),source="Manually attributed by you"}
 Refresh();return true
end
function Eco.DEExclusionRows()
 local rows={}
 for id in pairs(Store().exclusions) do
  local it=Eco.Item(tonumber(id) or Eco.BaseID(id))
  rows[#rows+1]={key="excluded:"..id,method="de",excludedItem=true,id=tonumber(id) or Eco.BaseID(id),label=it and it.name or id,
   icon=it and it.icon,itemQuality=it and it.quality,quality=0,verified=false,eligible=false,reasons={},why="Excluded by you.",d={modelReady=false}}
 end
 return rows
end

-- Exact convolution for an identical-price batch; bounded to avoid UI stalls.
-- Values are integer hundredths of copper, preserving the 5/15 percent cut.
-- Chernoff bound: P(sum of net returns <= 0) <= E[exp(-t*return)]^n.
-- Any t >= 0 gives a valid bound; minimization improves it without enumerating
-- combinations. This is conservative under the same independent yield model.
local function ConservativeBatch(result,values,unit,stack,mean,budget)
 local function moment(t)
  local sum=0
  for value,p in pairs(values) do sum=sum+p*math.exp(-t*(value/100-unit)/unit) end
  return sum
 end
 local lo,hi=0,32
 for i=1,60 do
  local a,b=(2*lo+hi)/3,(lo+2*hi)/3
  if moment(a)<moment(b) then hi=b else lo=a end
 end
 local mgf=moment((lo+hi)/2)+1e-12 -- round toward a weaker bound
 result.conservative=true
 if mgf>0 and mgf<1 then
  local logM=math.log(mgf)
  local n=math.max(stack,math.ceil(math.log(1-result.target)/logM/stack)*stack)
  if n<=5000 then
   result.quantity=n;result.cost=n*unit
   result.chance=1-math.exp(n*logM)
   result.profit=n*(mean-unit);result.overBudget=budget>0 and result.cost>budget
   return result
  end
 end
 result.reason="No conservative batch within 5000 items reaches the target at this price. Try a lower buyout."
 return result
end
local batchCache={}
function Eco.DEBatchSuggestion(row)
 if not row.trade or row.route~="de" or not row.def then return nil end
 local target=math.min(0.99,math.max(0.90,(Eco.DB().settings.deChance or 80)/100))
 local budget=Eco.DB().settings.deCapital or 0
 local unit=row.cost/row.qty
 local values,signature={}, {row.def.key,tostring(unit),tostring(row.qty),tostring(target),tostring(budget),tostring(Eco.cut)}
 local mean,totalP=0,0
 for _,m in ipairs(row.def.results) do
  local price=row.prices and row.prices[m[1]]
  if not price or not price.unit or price.unit<=0 then return {reason="Missing material prices; no batch suggestion."} end
  signature[#signature+1]=m[1]..":"..price.unit..":"..m[2]..":"..m[3]..":"..m[4]
  for q=m[3],m[4] do
   local v=floor(price.unit*q*(1-Eco.cut)*100+0.5)
   local probability=m[2]/(m[4]-m[3]+1)
   values[v]=(values[v] or 0)+probability;mean=mean+v/100*probability;totalP=totalP+probability
  end
 end
 if math.abs(totalP-1)>0.000001 then return {reason="Incomplete probability table; no batch suggestion."} end
 local key=table.concat(signature,"|")
 if batchCache.key==key then return batchCache.result end
 local result={target=target,unit=unit}
 if mean<=unit then
  result.reason="No positive expected profit: buying more does not fix the price."
 else
  local sums={[0]=1};local operations=0
  for n=1,50 do
   local nextSums,count={},0
   for sum,p in pairs(sums) do
    for value,chance in pairs(values) do
     operations=operations+1
     if operations>500000 then
      ConservativeBatch(result,values,unit,row.qty,mean,budget)
      batchCache={key=key,result=result};return result
     end
     local v=sum+value
     if not nextSums[v] then count=count+1 end
     nextSums[v]=(nextSums[v] or 0)+p*chance
    end
   end
   sums=nextSums
   local profitChance=0
   for value,chance in pairs(sums) do if value>unit*n*100+0.000001 then profitChance=profitChance+chance end end
   if n==1 then result.single=profitChance end
   if n%row.qty==0 and profitChance+0.000000001>=target then
    result.quantity=n;result.cost=n*unit;result.chance=math.min(1,profitChance)
    result.profit=n*(mean-unit);result.overBudget=budget>0 and result.cost>budget
    break
   end
  end
  if not result.quantity then ConservativeBatch(result,values,unit,row.qty,mean,budget) end
 end
 batchCache={key=key,result=result};return result
end

function Eco.DEWorkflowSheet(row)
 local s={buy={},search={},todo={},outcome={},fees={},assumptions={},excluded={}}
 if row.trade then
  s.total=row.cost
  s.batch=Eco.DEBatchSuggestion(row)
  s.buy={{id=row.id,link=row.link,name=row.label,qty=row.qty,max=row.cost/row.qty,total=row.cost}}
  s.search={Eco.Item(row.link or row.id).name}
  s.todo={"Recheck this auction's current buyout.",row.route=="vendor" and "Buy manually and sell the item to a vendor." or "Verify disenchant eligibility, buy manually, then collect the mail.",
   row.route=="de" and "In Bought items, mark the received item; disenchant it manually, then sell the materials." or "Do not disenchant this vendor resale opportunity."}
  s.outcome={{"Expected DE value after auction cut",row.expected and Eco.Money(row.expected) or "Missing material prices"},
   {"Vendor resale value",Eco.Money(row.vendor)},{"Estimated net profit",Eco.ProfitText(row.net)},
   {"Margin on purchase cost",string.format("%.1f%%",row.margin)},
   {"Recheck",row.check and row.check.status or "Not checked"},
   {"Price source",row.quick and "Scan summary; exact buyout must be checked" or "Exact buyout from the full scan"}}
  s.fees={string.format("Auction cut: %.0f%% (DE materials only).",Eco.cut*100)}
  s.assumptions={"Expected value is an average across possible outcomes, not a guaranteed result.","Unsuccessful listing deposits and sale delays are not included.","Recheck confirms availability at that instant only."}
  if row.def then
   s.assumptions[#s.assumptions+1]="Classic table: "..row.def.label.."; not validated for this server."
   for _,m in ipairs(row.def.results) do
    local it=Eco.Item(m[1]);local price=row.prices and row.prices[m[1]]
    s.outcome[#s.outcome+1]={string.format("%.1f%% x %.1f %s",m[2]*100,(m[3]+m[4])/2,it and it.name or m[1]),price and Eco.Money(price.unit).." each" or "No price"}
   end
   local seen=Eco.DESeen().lots[row.def.key]
   if seen then s.assumptions[#s.assumptions+1]=seen.n.." observed disenchants saved for comparison; the model is not automatically overwritten." end
  end
 elseif row.bagItem then
  s.todo={string.format("Locate bag %d, slot %d: %s.",row.bag.bag,row.bag.slot,row.label),
   row.marked and "Marked as purchased. Disenchant this item manually." or "Confirm that this is the purchased item using Mark purchased item.","Sell the resulting materials."}
  s.outcome={{"Tracking",row.marked and "Item GUID marked" or "Awaiting your confirmation"}}
  s.assumptions={"Only bag items matching a recorded purchase are shown. Equipment and previously owned GUIDs are excluded."}
 elseif row.journal then
  local p=row.purchase;s.total=p.cost
  s.todo={"Review the actual materials and compare their value with the purchase estimate."}
  s.outcome={{"Purchased",tostring(p.qty)},{"Observed disenchants",tostring(#p.outcomes)},
   {"Expected DE proceeds",p.expected and Eco.Money(p.expected) or "N/A"},
   {"Actual materials, valued at observation",row.observed and Eco.Money(row.observed) or "Not available"},
   {"Realized profit",p.sale and Eco.ProfitText(p.sale.net-p.cost-p.sale.loss) or "Record your actual sale proceeds below"}}
  for _,o in ipairs(p.outcomes) do for id,q in pairs(o.mats) do
   local it=Eco.Item(id);s.outcome[#s.outcome+1]={it and it.name or tostring(id),tostring(q)}
  end end
  s.assumptions={"Material valuation is unrealized. Enter only net proceeds from this purchase, after the auction cut, and lost deposits.","Recorded sale proceeds are attributed by you; this prevents mixing sales of materials from other sources."}
 elseif row.excludedItem then
  s.todo={"Use Restore item to allow this item in future scans."}
 end
 return s
end

