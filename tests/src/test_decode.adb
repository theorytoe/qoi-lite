with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;      use Ada.Text_IO;
with Interfaces;
with Qoi_Lite;

--  Tests for Qoi_Lite.Decode.  Known-answer cases are the inverse of the
--  encoder suite: the same independent oracle streams go in, the original
--  pixel buffers must come out.  Also covers encode/decode round trips
--  and the Read_Header accept/reject suite.

procedure Test_Decode is

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

   End_Pad : constant Qoi_Lite.Byte_Array := (1 .. 7 => 0, 8 => 1);

   --  14-byte file header oracle
   function Make_Header
      (W, H : Interfaces.Unsigned_32;
       Ch, Cs : Qoi_Lite.Byte) return Qoi_Lite.Byte_Array
   is (Magic_Bytes & U32_BE (W) & U32_BE (H) & Ch & Cs);

   --  N identical RGB pixels (V, V, V)
   function Grays (N : Positive; V : Qoi_Lite.Byte)
      return Qoi_Lite.Byte_Array is
      (1 .. 3 * N => V);

   --  Hex dump for failure diagnostics
   function Hex (B : Qoi_Lite.Byte_Array) return String is
      Hex_Chars : constant String := "0123456789ABCDEF";
      S : String (1 .. B'Length * 3);
   begin
      for I in B'Range loop
         S ((I - B'First) * 3 + 1) := Hex_Chars (Natural (B (I)) / 16 + 1);
         S ((I - B'First) * 3 + 2) := Hex_Chars (Natural (B (I)) mod 16 + 1);
         S ((I - B'First) * 3 + 3) := ' ';
      end loop;
      return S;
   end Hex;

   Lcg : Interfaces.Unsigned_32 := 16#C0FF_EE01#;

   --  Tiny deterministic LCG for the pixel generators
   function Rand return Interfaces.Unsigned_32 is
   begin
      Lcg := Lcg * 1_103_515_245 + 12_345;
      return Interfaces.Shift_Right (Lcg, 16);
   end Rand;

   --  Pseudo-random RGBA noise: mostly Op_RGB/Op_RGBA chunks
   function Noise_Pixels return Qoi_Lite.Byte_Array is
      B : Qoi_Lite.Byte_Array (1 .. 4 * 16 * 12);
   begin
      for I in B'Range loop
         B (I) := Qoi_Lite.Byte (Rand mod 256);
      end loop;
      return B;
   end Noise_Pixels;

   --  Smooth random walk: heavy Op_Diff/Op_Luma traffic
   function Walk_Pixels return Qoi_Lite.Byte_Array is
      B          : Qoi_Lite.Byte_Array (1 .. 3 * 31 * 17);
      P          : Positive := B'First;
      Rc, Gc, Bc : Integer := 128;
   begin
      while P + 2 <= B'Last loop
         B (P)     := Qoi_Lite.Byte (Rc);
         B (P + 1) := Qoi_Lite.Byte (Gc);
         B (P + 2) := Qoi_Lite.Byte (Bc);
         P := P + 3;
         Rc := (Rc + Natural (Rand mod 7) - 3 + 256) mod 256;
         Gc := (Gc + Natural (Rand mod 7) - 3 + 256) mod 256;
         Bc := (Bc + Natural (Rand mod 7) - 3 + 256) mod 256;
      end loop;
      return B;
   end Walk_Pixels;

   --  Decode Stream and require exact Description and exact pixels
   procedure Check_Decode
      (Name     : String;
       Stream   : Qoi_Lite.Byte_Array;
       Exp_Desc : Qoi_Lite.Description;
       Expected : Qoi_Lite.Byte_Array)
   is
      Dec  : Qoi_Lite.Byte_Array (0 .. 4095) := (others => 16#AA#);
      Last : Natural;
      Desc : Qoi_Lite.Description;
   begin
      Qoi_Lite.Decode (Stream, Desc, Dec (0 .. Expected'Length - 1), Last);
      Check (Name & ": length", Last = Expected'Length - 1);
      Check (Name & ": desc", Desc = Exp_Desc);
      if Dec (0 .. Last) = Expected then
         Check (Name & ": pixels", True);
      else
         Check (Name & ": pixels", False);
         Put_Line ("      expected: " & Hex (Expected));
         Put_Line ("      actual:   " & Hex (Dec (0 .. Last)));
      end if;
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  " & Name & ": raised "
                   & Ada.Exceptions.Exception_Name (E));
   end Check_Decode;

   --  Encode Pixels, decode the produced stream back, require equality
   procedure Check_Round_Trip
      (Name   : String;
       Pixels : Qoi_Lite.Byte_Array;
       Desc   : Qoi_Lite.Description)
   is
      Enc      : Qoi_Lite.Byte_Array (0 .. 65535) := (others => 16#AA#);
      Dec      : Qoi_Lite.Byte_Array (0 .. 65535) := (others => 16#BB#);
      Enc_Last : Natural;
      Dec_Last : Natural;
      Dec_Desc : Qoi_Lite.Description;
   begin
      Qoi_Lite.Encode (Pixels, Desc, Enc, Enc_Last);
      Qoi_Lite.Decode
         (Enc (0 .. Enc_Last), Dec_Desc, Dec (0 .. Pixels'Length - 1),
          Dec_Last);
      Check (Name & ": desc", Dec_Desc = Desc);
      Check (Name & ": length", Dec_Last = Pixels'Length - 1);
      if Dec (0 .. Dec_Last) = Pixels then
         Check (Name & ": pixels", True);
      else
         Check (Name & ": pixels", False);
         Put_Line ("      expected: " & Hex (Pixels));
         Put_Line ("      actual:   " & Hex (Dec (0 .. Dec_Last)));
      end if;
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  " & Name & ": raised "
                   & Ada.Exceptions.Exception_Name (E));
   end Check_Round_Trip;

   --  Decode must raise Decode_Error, or Constraint_Error when Want_CE
   procedure Expect_Decode_Raise
      (Name    : String;
       Stream  : Qoi_Lite.Byte_Array;
       Out_Len : Natural;
       Want_CE : Boolean)
   is
      Out_Buf : Qoi_Lite.Byte_Array (0 .. Out_Len - 1) := (others => 0);
      Last    : Natural;
      Desc    : Qoi_Lite.Description;
      Raised  : Boolean := False;
      Right   : Boolean := False;
   begin
      begin
         Qoi_Lite.Decode (Stream, Desc, Out_Buf, Last);
      exception
         when Constraint_Error =>
            Raised := True;
            Right  := Want_CE;
         when Qoi_Lite.Decode_Error =>
            Raised := True;
            Right  := not Want_CE;
      end;
      Check (Name, Raised and then Right);
   end Expect_Decode_Raise;

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

   --  ------------------------------------------------------------------
   --  Decode: the inverse of the encoder known-answer cases.  Oracle
   --  streams in, original pixel buffers out.
   --  ------------------------------------------------------------------

   Check_Decode ("decode_black_1x1",
                 Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad,
                 D1x1, (0, 0, 0));

   Check_Decode ("decode_diff_1x1",
                 Make_Header (1, 1, 3, 0) & 16#7F# & End_Pad,
                 D1x1, (1, 1, 1));

   Check_Decode ("decode_diff_to_luma",
                 Make_Header (1, 2, 3, 0) & (16#C0#, 16#A2#, 16#88#)
                 & End_Pad,
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 (0, 0, 0, 2, 2, 2));

   Check_Decode ("decode_luma_to_rgb",
                 Make_Header (1, 2, 3, 0)
                 & (16#C0#, 16#FE#, 16#20#, 16#20#, 16#20#) & End_Pad,
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 (0, 0, 0, 32, 32, 32));

   Check_Decode ("decode_luma_boundary",
                 Make_Header (1, 2, 3, 0) & (16#C0#, 16#BF#, 16#08#)
                 & End_Pad,
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 (0, 0, 0, 23, 31, 31));

   Check_Decode ("decode_index_hit",
                 Make_Header (1, 3, 3, 0)
                 & (16#FE#, 16#64#, 16#64#, 16#64#)
                 & (16#FE#, 16#C8#, 16#C8#, 16#C8#)
                 & 16#11# & End_Pad,
                 (Width => 1, Height => 3, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 (100, 100, 100, 200, 200, 200, 100, 100, 100));

   Check_Decode ("decode_hash_collision",
                 Make_Header (1, 3, 4, 0)
                 & (16#FE#, 16#32#, 16#32#, 16#32#)
                 & (16#FF#, 16#32#, 16#32#, 16#32#, 16#BF#)
                 & (16#FF#, 16#32#, 16#32#, 16#32#, 16#FF#) & End_Pad,
                 (Width => 1, Height => 3, Channels => 4,
                  Colorspace => Qoi_Lite.SRGB),
                 (50, 50, 50, 255, 50, 50, 50, 191, 50, 50, 50, 255));

   Check_Decode ("decode_rgba_change",
                 Make_Header (1, 2, 4, 0)
                 & (16#C0#, 16#FF#, 16#00#, 16#00#, 16#00#, 16#80#)
                 & End_Pad,
                 (Width => 1, Height => 2, Channels => 4,
                  Colorspace => Qoi_Lite.SRGB),
                 (0, 0, 0, 255, 0, 0, 0, 128));

   Check_Decode ("decode_wraparound",
                 Make_Header (1, 2, 3, 0) & (16#55#, 16#7F#) & End_Pad,
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 (255, 255, 255, 0, 0, 0));

   Check_Decode ("decode_run_61",
                 Make_Header (1, 61, 3, 0) & 16#FC# & End_Pad,
                 (Width => 1, Height => 61, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Grays (61, 0));

   Check_Decode ("decode_run_63",
                 Make_Header (1, 63, 3, 0) & (16#FD#, 16#C0#) & End_Pad,
                 (Width => 1, Height => 63, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Grays (63, 0));

   Check_Decode ("decode_run_flush_end",
                 Make_Header (1, 3, 3, 0) & 16#C2# & End_Pad,
                 (Width => 1, Height => 3, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Grays (3, 0));

   --  Colorspace byte must land in the Description
   declare
      Stream : Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad;
   begin
      Stream (Stream'First + 13) := 1;
      Check_Decode ("decode_colorspace_linear", Stream,
                    (Width => 1, Height => 1, Channels => 3,
                     Colorspace => Qoi_Lite.Linear),
                    (0, 0, 0));
   end;

   --  Nonzero array bounds must not disturb decoding
   declare
      Stream : constant Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad;
      Dec    : Qoi_Lite.Byte_Array (100 .. 599) := (others => 16#AA#);
      Last   : Natural;
      Desc   : Qoi_Lite.Description;
   begin
      Qoi_Lite.Decode (Stream, Desc, Dec (100 .. 102), Last);
      Check ("decode_nonzero_bounds: Last", Last = 102);
      Check ("decode_nonzero_bounds: pixels",
             Desc = D1x1 and then Dec (100 .. 102) = (0, 0, 0));
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  decode_nonzero_bounds: raised "
                   & Ada.Exceptions.Exception_Name (E));
   end;

   --  Decode validation: malformed headers raise Decode_Error
   declare
      Bad : Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad;
   begin
      Bad (Bad'First) := 16#70#;  --  break the magic
      Expect_Decode_Raise ("reject bad magic", Bad, 3, Want_CE => False);
   end;

   Expect_Decode_Raise ("reject decode width=0",
                        Make_Header (0, 1, 3, 0) & 16#C0# & End_Pad,
                        3, Want_CE => False);

   Expect_Decode_Raise ("reject decode height=0",
                        Make_Header (1, 0, 3, 0) & 16#C0# & End_Pad,
                        3, Want_CE => False);

   Expect_Decode_Raise ("reject decode channels=2",
                        Make_Header (1, 1, 2, 0) & 16#C0# & End_Pad,
                        3, Want_CE => False);

   Expect_Decode_Raise ("reject decode colorspace=2",
                        Make_Header (1, 1, 3, 2) & 16#C0# & End_Pad,
                        3, Want_CE => False);

   Expect_Decode_Raise ("reject truncated stream", (1 .. 13 => 0),
                        3, Want_CE => False);

   --  Valid stream, but the output buffer is too small (1x1 RGB needs 3)
   Expect_Decode_Raise ("reject decode small output",
                        Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad,
                        2, Want_CE => True);

   --  ------------------------------------------------------------------
   --  Encode -> decode round trips
   --  ------------------------------------------------------------------

   Check_Round_Trip ("roundtrip_black_1x1", (0, 0, 0), D1x1);

   Check_Round_Trip ("roundtrip_wraparound", (255, 255, 255, 0, 0, 0),
                     (Width => 1, Height => 2, Channels => 3,
                      Colorspace => Qoi_Lite.SRGB));

   Check_Round_Trip ("roundtrip_index_hit",
                     (100, 100, 100, 200, 200, 200, 100, 100, 100),
                     (Width => 1, Height => 3, Channels => 3,
                      Colorspace => Qoi_Lite.SRGB));

   Check_Round_Trip ("roundtrip_hash_collision",
                     (50, 50, 50, 255, 50, 50, 50, 191, 50, 50, 50, 255),
                     (Width => 1, Height => 3, Channels => 4,
                      Colorspace => Qoi_Lite.SRGB));

   Check_Round_Trip ("roundtrip_rgba_change",
                     (0, 0, 0, 255, 0, 0, 0, 128),
                     (Width => 1, Height => 2, Channels => 4,
                      Colorspace => Qoi_Lite.SRGB));

   --  Multi-chunk run: 200 pixels forces split run chunks
   Check_Round_Trip ("roundtrip_run_200", Grays (200, 42),
                     (Width => 1, Height => 200, Channels => 3,
                      Colorspace => Qoi_Lite.SRGB));

   --  Pseudo-random RGBA noise: mostly Op_RGB/Op_RGBA chunks
   Check_Round_Trip ("roundtrip_noise", Noise_Pixels,
                     (Width => 16, Height => 12, Channels => 4,
                      Colorspace => Qoi_Lite.SRGB));

   --  Smooth random walk: heavy Op_Diff/Op_Luma traffic
   Check_Round_Trip ("roundtrip_walk", Walk_Pixels,
                     (Width => 31, Height => 17, Channels => 3,
                      Colorspace => Qoi_Lite.SRGB));

   --  ------------------------------------------------------------------
   --  Read_Header: accept, then reject
   --  ------------------------------------------------------------------

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

end Test_Decode;
