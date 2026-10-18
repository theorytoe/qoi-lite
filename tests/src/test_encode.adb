with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;      use Ada.Text_IO;
with Interfaces;
with Qoi_Lite;

--  Known-answer tests for Qoi_Lite.Encode, driven by cases.md.
--  Expected streams come from an independent header oracle below, never
--  from the library under test.  Decode is exercised by test_decode.

procedure Test_Encode is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;
   use type Qoi_Lite.Byte_Array;

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

   --  Independent big-endian u32 oracle (mirrors Qoi_Lite.Write_32)
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

   --  Encode Pixels and require the exact full stream and exact Last
   procedure Check_Stream
      (Name     : String;
       Pixels   : Qoi_Lite.Byte_Array;
       Desc     : Qoi_Lite.Description;
       Expected : Qoi_Lite.Byte_Array)
   is
      Out_Buf : Qoi_Lite.Byte_Array (0 .. 4095) := (others => 16#AA#);
      Last    : Natural;
   begin
      Qoi_Lite.Encode (Pixels, Desc, Out_Buf, Last);
      Check (Name & ": length", Last = Expected'Length - 1);
      if Out_Buf (0 .. Last) = Expected then
         Check (Name & ": bytes", True);
      else
         Check (Name & ": bytes", False);
         Put_Line ("      expected: " & Hex (Expected));
         Put_Line ("      actual:   " & Hex (Out_Buf (0 .. Last)));
      end if;
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  " & Name & ": raised "
                   & Ada.Exceptions.Exception_Name (E));
   end Check_Stream;

   --  Encode must raise Constraint_Error for these arguments
   procedure Expect_Raise
      (Name    : String;
       Pixels  : Qoi_Lite.Byte_Array;
       Desc    : Qoi_Lite.Description;
       Out_Len : Natural)
   is
      Out_Buf : Qoi_Lite.Byte_Array (0 .. Out_Len - 1) := (others => 0);
      Last    : Natural;
      Raised  : Boolean := False;
   begin
      begin
         Qoi_Lite.Encode (Pixels, Desc, Out_Buf, Last);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      Check (Name, Raised);
   end Expect_Raise;

   D1x1 : constant Qoi_Lite.Description :=
      (Width => 1, Height => 1, Channels => 3, Colorspace => Qoi_Lite.SRGB);

begin

   --  Qoi_Lite.Write_32 byte order
   declare
      B : Qoi_Lite.Byte_Array (1 .. 4) := (others => 0);
      P : Natural := 1;
   begin
      Qoi_Lite.Write_32 (B, P, 16#DE_AD_BE_EF#);
      Check ("write_32 big-endian",
             B = (16#DE#, 16#AD#, 16#BE#, 16#EF#) and then P = 5);
   exception
      when E : others =>
         Failed := Failed + 1;
         Put_Line ("FAIL  write_32 big-endian: raised "
                   & Ada.Exceptions.Exception_Name (E));
   end;

   --  #1 black_1x1: first pixel equals startup prev, flushed at end
   Check_Stream ("black_1x1", (0, 0, 0), D1x1,
                 Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad);

   --  #2 diff_1x1: QOI_OP_DIFF with dr = dg = db = +1
   Check_Stream ("diff_1x1", (1, 1, 1), D1x1,
                 Make_Header (1, 1, 3, 0) & 16#7F# & End_Pad);

   --  #3 diff_to_luma: DIFF rejects vr = +2, LUMA catches it
   Check_Stream ("diff_to_luma", (0, 0, 0, 2, 2, 2),
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 2, 3, 0)
                 & (16#C0#, 16#A2#, 16#88#) & End_Pad);

   --  #4 luma_to_rgb: LUMA rejects vg = +32, falls through to QOI_OP_RGB
   Check_Stream ("luma_to_rgb", (0, 0, 0, 32, 32, 32),
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 2, 3, 0)
                 & (16#C0#, 16#FE#, 16#20#, 16#20#, 16#20#) & End_Pad);

   --  #5 luma_boundary: vg = +31 max, vg_r = -8 allowed
   Check_Stream ("luma_boundary", (0, 0, 0, 23, 31, 31),
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 2, 3, 0)
                 & (16#C0#, 16#BF#, 16#08#) & End_Pad);

   --  #6 index_hit: (100,100,100) hashes to slot 17, revisit -> QOI_OP_INDEX
   Check_Stream ("index_hit",
                 (100, 100, 100, 200, 200, 200, 100, 100, 100),
                 (Width => 1, Height => 3, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 3, 3, 0)
                 & (16#FE#, 16#64#, 16#64#, 16#64#)
                 & (16#FE#, 16#C8#, 16#C8#, 16#C8#)
                 & 16#11# & End_Pad);

   --  #7 hash_collision: delta a = -64 preserves the hash slot, so INDEX
   --  must not fire for either revisit
   Check_Stream ("hash_collision",
                 (50, 50, 50, 255, 50, 50, 50, 191, 50, 50, 50, 255),
                 (Width => 1, Height => 3, Channels => 4,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 3, 4, 0)
                 & (16#FE#, 16#32#, 16#32#, 16#32#)
                 & (16#FF#, 16#32#, 16#32#, 16#32#, 16#BF#)
                 & (16#FF#, 16#32#, 16#32#, 16#32#, 16#FF#) & End_Pad);

   --  #8 rgba_change: QOI_OP_RGBA on alpha change
   Check_Stream ("rgba_change", (0, 0, 0, 255, 0, 0, 0, 128),
                 (Width => 1, Height => 2, Channels => 4,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 2, 4, 0)
                 & (16#C0#, 16#FF#, 16#00#, 16#00#, 16#00#, 16#80#)
                 & End_Pad);

   --  #9 wraparound: the reference wraps the channel delta through a
   --  signed char (255 - 0 -> -1, 0 - 255 -> +1).  Replicated here for
   --  byte-identical output with the official corpus; requires the
   --  encoder to wrap deltas into the signed 8-bit range.
   Check_Stream ("wraparound", (255, 255, 255, 0, 0, 0),
                 (Width => 1, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 2, 3, 0) & (16#55#, 16#7F#) & End_Pad);

   --  #10a run_61: run flushes at end only.  Black pixels so the first
   --  pixel joins the run (prev starts black); cases.md's FB is off by
   --  one: a run of 61 encodes as C0 or 60 = FC
   Check_Stream ("run_61", Grays (61, 0),
                 (Width => 1, Height => 61, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 61, 3, 0) & 16#FC# & End_Pad);

   --  #10b run_62: max QOI_OP_RUN value, flushed mid-loop.  cases.md says
   --  FF, but FF is the Op_RGBA tag: max run chunk is C0 or 61 = FD
   Check_Stream ("run_62", Grays (62, 0),
                 (Width => 1, Height => 62, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 62, 3, 0) & 16#FD# & End_Pad);

   --  #10c run_63: split 62 + 1 (cases.md's FF is impossible, see 10b)
   Check_Stream ("run_63", Grays (63, 0),
                 (Width => 1, Height => 63, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 63, 3, 0) & (16#FD#, 16#C0#) & End_Pad);

   --  #10d run_64: split 62 + 2 (cases.md says FF FF, corrected: FD then C1)
   Check_Stream ("run_64", Grays (64, 0),
                 (Width => 1, Height => 64, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 64, 3, 0) & (16#FD#, 16#C1#) & End_Pad);

   --  #11 run_flush_end: single run chunk of 3
   Check_Stream ("run_flush_end", Grays (3, 0),
                 (Width => 1, Height => 3, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB),
                 Make_Header (1, 3, 3, 0) & 16#C2# & End_Pad);

   --  #12 channels_3_vs_4: identical chunk streams, header byte differs
   declare
      function Build (Channels : Positive) return Qoi_Lite.Byte_Array is
         B : Qoi_Lite.Byte_Array (1 .. 16 * Channels) := (others => 255);
         P : Natural := 1;
      begin
         for Y in 0 .. 3 loop
            for X in 0 .. 3 loop
               B (P)     := Qoi_Lite.Byte (16 * X + Y);
               B (P + 1) := Qoi_Lite.Byte (32 * Y + X);
               B (P + 2) := Qoi_Lite.Byte (8 * X + 4 * Y);
               P := P + Channels;
            end loop;
         end loop;
         return B;
      end Build;

      Out3, Out4 : Qoi_Lite.Byte_Array (0 .. 4095) := (others => 0);
      L3, L4     : Natural;
   begin
      Qoi_Lite.Encode (Build (3),
                  (Width => 4, Height => 4, Channels => 3,
                   Colorspace => Qoi_Lite.SRGB), Out3, L3);
      Qoi_Lite.Encode (Build (4),
                  (Width => 4, Height => 4, Channels => 4,
                   Colorspace => Qoi_Lite.SRGB), Out4, L4);
      Check ("channels_3_vs_4: headers equal but channels field",
             Out3 (0 .. 11) = Out4 (0 .. 11)
             and then Out3 (12) = 3 and then Out4 (12) = 4
             and then Out3 (13) = Out4 (13));
      Check ("channels_3_vs_4: identical chunk streams",
             Out3 (14 .. L3 - 8) = Out4 (14 .. L4 - 8));
   end;

   --  #13 colorspace_linear: header-only metadata, chunks unaffected
   declare
      Expected : Qoi_Lite.Byte_Array :=
         Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad;
   begin
      Expected (Expected'First + 13) := 1;  --  0-based byte 13: colorspace
      Check_Stream ("colorspace_linear", (0, 0, 0),
                    (Width => 1, Height => 1, Channels => 3,
                     Colorspace => Qoi_Lite.Linear),
                    Expected);
   end;

   --  Nonzero array bounds must not disturb encoding
   declare
      Input   : constant Qoi_Lite.Byte_Array (10 .. 21) := (others => 0);
      Out_Buf : Qoi_Lite.Byte_Array (100 .. 599) := (others => 16#AA#);
      Last    : Natural;
   begin
      Qoi_Lite.Encode (Input (10 .. 12), D1x1, Out_Buf, Last);
      Check ("nonzero_bounds: Last", Last = 122);
      Check ("nonzero_bounds: stream",
             Out_Buf (100 .. Last)
             = Make_Header (1, 1, 3, 0) & 16#C0# & End_Pad);
   end;

   --  Validation: zero dimensions
   Expect_Raise ("reject width=0", (0, 0, 0),
                 (Width => 0, Height => 1, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB), 1024);
   Expect_Raise ("reject height=0", (0, 0, 0),
                 (Width => 1, Height => 0, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB), 1024);

   --  Validation: pixel buffer length mismatch (2x2x3 needs 12, got 5)
   Expect_Raise ("reject buf length", (1, 2, 3, 4, 5),
                 (Width => 2, Height => 2, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB), 1024);

   --  Validation: output smaller than worst case (10x10 RGBA needs 522)
   Expect_Raise ("reject small output", (1 .. 400 => 0),
                 (Width => 10, Height => 10, Channels => 4,
                  Colorspace => Qoi_Lite.SRGB), 100);

   --  Validation: width * height overflow guard
   Expect_Raise ("reject overflow", (0, 0, 0),
                 (Width => 1_000_000, Height => 1_000_000, Channels => 3,
                  Colorspace => Qoi_Lite.SRGB), 1024);

   Put_Line ("passed:" & Passed'Image & "  failed:" & Failed'Image);
   if Failed > 0 then
      Set_Exit_Status (Failure);
   end if;

end Test_Encode;
