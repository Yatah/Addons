public static class BronzeArt {
 public static void Metal(Img im) {
  for(int i=0;i<im.R.Length;i++) {
   float l=im.R[i]*.299f+im.G[i]*.587f+im.B[i]*.114f;
   im.R[i]=System.Math.Min(1f,l*1.55f); im.G[i]=System.Math.Min(1f,l*1.10f); im.B[i]=l*.53f;
  }
 }
 public static void Leather(Img im, Img tex) {
  for(int y=0;y<im.H;y++) for(int x=0;x<im.W;x++) {
   int i=im.I(x,y); if(im.A[i]<=0) continue;
   int j=tex.I(380+x%570,410+y%380);
   im.R[i]=tex.R[j]*1.15f; im.G[i]=tex.G[j]*.92f; im.B[i]=tex.B[j]*.72f;
   im.A[i]=System.Math.Min(1f,im.A[i]*1.17f);
  }
 }
}
