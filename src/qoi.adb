package body Qoi is

   procedure Encode
      (Buf    : Byte_Array;
       Desc   : Description;
       Output : out Byte_Array;
       Last   : out Natural)
   is
      Cur, Max_Size, Run : Integer;
      Index              : array (0 .. 63) of Pixel;
   begin
      null;
   end Encode;

   procedure Decode
      (Data   : Byte_Array;
       Output : out Byte_Array;
       Last   : out Natural;
       Desc   : out Description)
   is
   begin
      null;
   end Decode;

   function Hash (P : Pixel) return Interfaces.Unsigned_32 is
      use type Interfaces.Unsigned_32;
   begin
      --  from impl.
      --  (C.rgba.r*3 + C.rgba.g*5 + C.rgba.b*7 + C.rgba.a*11)
      return (Interfaces.Unsigned_32 (P.R) * 3
              + Interfaces.Unsigned_32 (P.G) * 5
              + Interfaces.Unsigned_32 (P.B) * 7
              + Interfaces.Unsigned_32 (P.A) * 11) mod 64;
   end Hash;

end Qoi;
