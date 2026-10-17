with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;      use Ada.Text_IO;
with Interfaces;
with Qoi_Lite;

--  Known-answer and rejection tests for Qoi_Lite.Read_Header, run as a
--  standalone executable.  Header fixtures are built by an independent
--  big-endian oracle below, never by the library under test.  Rejection
--  cases must raise Decode_Error specifically: a return, or a
--  Constraint_Error from a missing check, counts as a failure.

procedure Test_Read_Header is

   use type Interfaces.Unsigned_32;
   use type Qoi_Lite.Byte_Array;
   use type Qoi_Lite.Description;

   Passed, Failed : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      if Cond then
         Passed := Passed + 1;
      else
         Failed := Failed + 1;
         Put_Line ("FAIL  " & Name);
      end if;
   end Check;

   --  Independent big-endian u32 oracle (mirrors the QOI spec)
   function U32_BE (V : Interfaces.Unsigned_32) return Qoi_Lite.Byte_Array is
      (1 => Qoi_Lite.Byte (Interfaces.Shift_Right (V, 24) and 16#FF#),
       2 => Qoi_Lite.Byte (Interfaces.Shift_Right (V, 16) and 16#FF#),
       3 => Qoi_Lite.Byte (Interfaces.Shift_Right (V, 8) and 16#FF#),
       4 => Qoi_Lite.Byte (V and 16#FF#));

   Magic_Bytes : constant Qoi_Lite.Byte_Array :=
      (16#71#, 16#6F#, 16#69#, 16#66#);

   --  14-byte file header oracle
   function Make_Header
      (W, H : Interfaces.Unsigned_32; Ch, Cs : Qoi_Lite.Byte)
      return Qoi_Lite.Byte_Array
   is (Magic_Bytes & U32_BE (W) & U32_BE (H) & Ch & Cs);

   D1x1 : constant Qoi_Lite.Description :=
      (Width => 1, Height => 1, Channels => 3, Colorspace => Qoi_Lite.SRGB);

   --  Compact description rendering for failure diagnostics
   function Img (D : Qoi_Lite.Description) return String is
      (Interfaces.Unsigned_32'Image (D.Width) & "x"
       & Interfaces.Unsigned_32'Image (D.Height)
       & " ch=" & Qoi_Lite.Channel_Count'Image (D.Channels)
       & " cs=" & Qoi_Lite.Colorspace_Kind'Image (D.Colorspace));

   --  Read_Header must return exactly Expected
   procedure Check_Header
      (Name     : String;
       Data     : Qoi_Lite.Byte_Array;
       Expected : Qoi_Lite.Description)
   is
      Got : Qoi_Lite.Description;
   begin
      Got := Qoi_Lite.Read_Header (Data);
      if Got = Expected then
         Check (Name, True);
      else
         Check (Name, False);
         Put_Line ("      got:  " & Img (Got));
         Put_Line ("      want: " & Img (Expected));
      end if;
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  " & Name & ": raised "
                   & Ada.Exceptions.Exception_Name (E));
   end Check_Header;

   --  Read_Header must reject with Decode_Error specifically.  A normal
   --  return, a Constraint_Error from a missing range check, or any
   --  other exception is a failure.
   procedure Expect_Decode_Error
      (Name : String;
       Data : Qoi_Lite.Byte_Array)
   is
      Got : Qoi_Lite.Description;
   begin
      Got := Qoi_Lite.Read_Header (Data);
      Check (Name, False);
      Put_Line ("      returned " & Img (Got) & " instead of raising");
   exception
      when Qoi_Lite.Decode_Error =>
         Check (Name, True);
      when E : others =>
         Check (Name, False);
         Put_Line ("      raised "
                   & Ada.Exceptions.Exception_Name (E)
                   & " instead of Decode_Error");
   end Expect_Decode_Error;

begin

   --  ==== Accept: valid headers ====

   Check_Header ("minimal_rgb", Make_Header (1, 1, 3, 0), D1x1);

   Check_Header ("rgba_linear", Make_Header (2, 3, 4, 1),
                 (Width => 2, Height => 3, Channels => 4,
                  Colorspace => Qoi_Lite.Linear));

   --  Byte-order sentinel: an asymmetric word catches reversed shifts
   --  or half-swapped endianness in Read_32
   Check_Header ("endian_word", Make_Header (16#01_02_03_04#, 1, 3, 0),
                 (Width => 16#01_02_03_04#, Height => 1, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB));

   --  A slice with nonzero'First must not disturb the parse
   declare
      Store : Qoi_Lite.Byte_Array (10 .. 63) := (others => 16#AA#);
   begin
      Store (10 .. 23) := Make_Header (2, 3, 4, 1);
      Check_Header ("nonzero_first", Store (10 .. 23),
                    (Width => 2, Height => 3, Channels => 4,
                     Colorspace => Qoi_Lite.Linear));
   end;

   --  Contract: only the first Header_Size bytes are inspected.  Chunk
   --  and padding bytes after the header are not Read_Header's business.
   declare
      Data : constant Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) & (1 .. 40 => 16#55#);
   begin
      Check_Header ("trailing_junk", Data, D1x1);
   end;

   --  Largest accepted dimensions: Height < Pixels_Max / Width strictly
   Check_Header ("dims_max_h", Make_Header (1, 399_999_999, 3, 0),
                 (Width => 1, Height => 399_999_999, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB));
   Check_Header ("dims_max_product", Make_Header (2, 199_999_999, 3, 0),
                 (Width => 2, Height => 199_999_999, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB));

   --  ==== Reject: each case must raise Decode_Error ====

   Expect_Decode_Error ("reject empty", (1 .. 0 => 0));

   declare
      Short : constant Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) (1 .. 13);
   begin
      Expect_Decode_Error ("reject truncated_13", Short);
   end;

   --  Magic corruption, first and last byte
   declare
      Bad_First : Qoi_Lite.Byte_Array := Make_Header (1, 1, 3, 0);
      Bad_Last  : Qoi_Lite.Byte_Array := Make_Header (1, 1, 3, 0);
   begin
      Bad_First (Bad_First'First) := 16#58#;  --  "xoif"
      Expect_Decode_Error ("reject magic_first", Bad_First);
      Bad_Last (Bad_Last'First + 3) := 16#65#;  --  "qoie"
      Expect_Decode_Error ("reject magic_last", Bad_Last);
   end;

   --  Zero dimensions
   Expect_Decode_Error ("reject width=0", Make_Header (0, 1, 3, 0));
   Expect_Decode_Error ("reject height=0", Make_Header (1, 0, 3, 0));

   --  Width * height guard: Height >= Pixels_Max / Width must reject
   Expect_Decode_Error ("reject overflow h=max",
                        Make_Header (1, 400_000_000, 3, 0));
   Expect_Decode_Error ("reject overflow w=2",
                        Make_Header (2, 200_000_000, 3, 0));
   Expect_Decode_Error ("reject overflow huge_w",
                        Make_Header (16#FFFF_FFFF#, 1, 3, 0));

   --  Channel count outside 3 .. 4
   Expect_Decode_Error ("reject channels=0", Make_Header (1, 1, 0, 0));
   Expect_Decode_Error ("reject channels=2", Make_Header (1, 1, 2, 0));
   Expect_Decode_Error ("reject channels=5", Make_Header (1, 1, 5, 0));
   Expect_Decode_Error ("reject channels=255", Make_Header (1, 1, 255, 0));

   --  Colorspace outside 0 .. 1
   Expect_Decode_Error ("reject colorspace=2", Make_Header (1, 1, 3, 2));
   Expect_Decode_Error ("reject colorspace=255",
                        Make_Header (1, 1, 3, 255));

   --  Cross-consistency: Encode's header must parse back to the input
   --  Description.  Unlike the fixtures above, this one exercises the
   --  Write_32/Read_32 pair on purpose.
   declare
      Out_Buf : Qoi_Lite.Byte_Array (0 .. 1023) := (others => 16#AA#);
      Last    : Natural;
   begin
      Qoi_Lite.Encode ((0, 0, 0), D1x1, Out_Buf, Last);
      Check_Header ("roundtrip_header", Out_Buf (0 .. 13), D1x1);
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  roundtrip_header: raised "
                   & Ada.Exceptions.Exception_Name (E));
   end;

   Put_Line ("passed:" & Passed'Image & "  failed:" & Failed'Image);
   if Failed > 0 then
      Set_Exit_Status (Failure);
   end if;

end Test_Read_Header;
