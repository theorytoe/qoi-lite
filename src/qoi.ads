with Interfaces;
package Qoi is

   subtype Byte is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of Byte;

   Pixels_Max  : constant := 400_000_000;
   Header_Size : constant := 14;

   type Colorspace_Kind is (SRGB, Linear);
   for Colorspace_Kind use (SRGB => 0, Linear => 1);
   for Colorspace_Kind'Size use 8;

   type Channel_Count is new Byte range 3 .. 4;

   --  header
   type Description is record
      Width      : Interfaces.Unsigned_32;
      Height     : Interfaces.Unsigned_32;
      Channels   : Channel_Count;
      Colorspace : Colorspace_Kind;
   end record;

   Op_Index : constant Byte := 2#00_000000#;  --  00xxxxxx
   Op_Diff  : constant Byte := 2#01_000000#;  --  01xxxxxx
   Op_Luma  : constant Byte := 2#10_000000#;  --  10xxxxxx
   Op_Run   : constant Byte := 2#11_000000#;  --  11xxxxxx
   Op_RGB   : constant Byte := 2#1111_1110#;  --  11111110
   Op_RGBA  : constant Byte := 2#1111_1111#;  --  11111111

   MMask : constant Byte := 2#11_000000#;

   Magic : constant String := "qoif";

   --  TODO: end marker

   type Pixel is record
      R, G, B, A : Byte := 0;
   end record
     with Size => 32;

   --  packing struct
   for Pixel use record
      R at 0 range 0 .. 7;
      G at 1 range 0 .. 7;
      B at 2 range 0 .. 7;
      A at 3 range 0 .. 7;
   end record;

   --  TODO: check semantics of 32bit type punt cmp in ref impl.
   --  function As_Word is new Ada.Unchecked_Conversion
   --    (Source => Pixel, Target => Interfaces.Unsigned_32);

   procedure Encode
      (Buf    : Byte_Array;
       Desc   : Description;
       Output : out Byte_Array;
       Last   : out Natural);

   function Hash (P : Pixel) return Interfaces.Unsigned_32;

end Qoi;
