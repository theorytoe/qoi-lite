package body Qoi_Lite is

   --  Write a uint32 into byte array Bytes at position specified by Pos
   procedure Write_32
      (Bytes : in out Byte_Array;
       Pos   : in out Natural;
       V     : Interfaces.Unsigned_32)
   is
      use type Interfaces.Unsigned_32;
   begin
      Bytes (Pos)     := Byte (Interfaces.Shift_Right (V, 24) and 16#FF#);
      Bytes (Pos + 1) := Byte (Interfaces.Shift_Right (V, 16) and 16#FF#);
      Bytes (Pos + 2) := Byte (Interfaces.Shift_Right (V, 8)  and 16#FF#);
      Bytes (Pos + 3) := Byte (V and 16#FF#);
      Pos := Pos + 4;
   end Write_32;

   --  Read a uint32 from byte array Bytes at position Pos
   function Read_32
      (Bytes : Byte_Array;
       Pos   : in out Natural)
       return Interfaces.Unsigned_32
   is
      use type Interfaces.Unsigned_32;

      A : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Bytes
         (Pos));
      B : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Bytes
         (Pos + 1));
      C : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Bytes
         (Pos + 2));
      D : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Bytes
         (Pos + 3));
   begin
      Pos := Pos + 4;
      return Interfaces.Shift_Left (A, 24)
              or Interfaces.Shift_Left (B, 16)
              or Interfaces.Shift_Left (C, 8)
              or D;
   end Read_32;

   procedure Encode
      (Buf    : Byte_Array;
       Desc   : Description;
       Output : out Byte_Array;
       Last   : out Natural)
   is
      use type Interfaces.Unsigned_32;
      use type Byte;

      Px_Count : constant Integer :=
         Integer (Desc.Width) * Integer (Desc.Height);
      Stride : constant Integer := Integer (Desc.Channels);

      --  Worst case size
      Max_Size : constant Integer :=
         Px_Count * (Stride + 1) + Header_Size + Pad_Size;

      Zero_Pixel : constant Pixel := (0, 0, 0, 0);

      Pad : constant Byte_Array (1 .. Pad_Size) :=
         (1 .. Pad_Size - 1 => 0, Pad_Size => Byte (1));

      --  Zeroed index array
      Index : Pixel_Table := (others => Zero_Pixel);

      Cur     : Integer := Output'First;
      Run     : Natural := 0;
      Px_Pos  : Natural := Buf'First;
      Px      : Pixel;
      Px_Prev : Pixel := (R => 0, G => 0, B => 0, A => 255);

      Vr, Vg, Vb, Vg_R, Vg_B : Integer;

      --  write byte helper
      procedure Put
         (B : Byte;
          Cur : in out Integer;
          Buf : in out Byte_Array)
      is begin
         Buf (Cur) := B;
         Cur := Cur + 1;
      end Put;

      --  Wrap a channel delta into the signed 8-bit range: the reference
      --  computes deltas in signed char, so 255 - 0 is -1, not +255, and
      --  0 - 255 is +1, not -255
      function Wrap_S8 (V : Integer) return Integer is
         (if V > 127 then V - 256
          elsif V < -128 then V + 256
          else V);

   begin

      --  Validation
      if Desc.Width = 0
         or else Desc.Height = 0
         or else Desc.Height >= Pixels_Max / Desc.Width
         or else Output'Length < Max_Size --  TODO: do we really need this?
                                          --  if the caller explicitly knows
                                          --  the size of the image, is this
                                          --  check really needed?
         or else Buf'Length /= Px_Count * Stride
      then
         raise Constraint_Error with "Encode: invalid buffer or description";
      end if;

      --  Write char by char
      for I in Magic'Range loop
         Output (Cur) := Byte (Character'Pos (Magic (I)));
         Cur := Cur + 1;
      end loop;

      --  other writes
      Write_32 (Output, Cur, Desc.Width);
      Write_32 (Output, Cur, Desc.Height);
      Put (Byte (Desc.Channels), Cur, Output);
      Put (Byte (Colorspace_Kind'Pos (Desc.Colorspace)), Cur, Output);

      --  Loop through Pixels
      Px := Px_Prev;
      for P in 1 .. Px_Count loop
         Px.R := Buf (Px_Pos);
         Px.G := Buf (Px_Pos + 1);
         Px.B := Buf (Px_Pos + 2);
         if Desc.Channels = 4 then
            Px.A := Buf (Px_Pos + 3);
         end if;

         if Px = Px_Prev then
            Run := Run + 1;

            if Run = 62 then
               Put (Op_Run or Byte (Run - 1), Cur, Output);
               Run := 0;
            end if;
         else
            if Run > 0 then
               Put (Op_Run or Byte (Run - 1), Cur, Output);
               Run := 0;
            end if;

            declare
               --  Check running color table
               Slot : constant Slot_Index := Color_Hash (Px);
            begin
               if Index (Slot) = Px then
                  Put (Op_Index or Byte (Slot), Cur, Output);
               else
                  Index (Slot) := Px;

                  --  Alpha unchanged?
                  if Px.A = Px_Prev.A then
                     Vr := Wrap_S8 (Integer (Px.R) - Integer (Px_Prev.R));
                     Vg := Wrap_S8 (Integer (Px.G) - Integer (Px_Prev.G));
                     Vb := Wrap_S8 (Integer (Px.B) - Integer (Px_Prev.B));

                     Vg_R := Vr - Vg;  --  Red delta rel. 2 green
                     Vg_B := Vb - Vg;  --  Blue delta rel. 2 green

                     --  Op_Diff: all three diffs within -2..1 -> 1 byte
                     --  stored biased +2 to fit in 2 bits
                     if Vr in -2 .. 1
                        and then Vg in -2 .. 1
                        and then Vb in -2 .. 1
                     then
                        Put (Op_Diff
                             or Interfaces.Shift_Left (Byte (Vr + 2), 4)
                             or Interfaces.Shift_Left (Byte (Vg + 2), 2)
                             or Byte (Vb + 2), Cur, Output);

                     --  QOI_OP_LUMA: green diff within -32..31 and the
                     --  red/blue residuals (diff minus green diff) within
                     --  -8..7 -> 2 bytes. Encoding the larger green delta
                     --  plus small residuals covers the common case where
                     --  all channels drift together. Biases: +32 and +8.
                     elsif Vg in -32 .. 31
                        and then Vg_R in -8 .. 7
                        and then Vg_B in -8 .. 7
                     then
                        Put (Op_Luma or Byte (Vg + 32), Cur, Output);
                        Put (Interfaces.Shift_Left (Byte (Vg_R + 8), 4)
                             or Byte (Vg_B + 8), Cur, Output);

                     --  QOI_OP_RGB: diffs too large -> spell out RGB in
                     --  full (4 bytes). Alpha stays implicit.
                     else
                        Put (Op_RGB, Cur, Output);
                        Put (Px.R, Cur, Output);
                        Put (Px.G, Cur, Output);
                        Put (Px.B, Cur, Output);
                     end if;
                  else

                     --  Alpha pixel
                     Put (Op_RGBA, Cur, Output);
                     Put (Px.R, Cur, Output);
                     Put (Px.G, Cur, Output);
                     Put (Px.B, Cur, Output);
                     Put (Px.A, Cur, Output);

                  end if;
               end if;
            end;
         end if;
         Px_Prev := Px;
         Px_Pos := Px_Pos + Stride;
      end loop;

      if Run > 0 then
         Put (Op_Run or Byte (Run - 1), Cur, Output);
      end if;

      --  slap the last bit of padding on
      Output (Cur .. Cur + Pad_Size - 1) := Pad;
      Last := Cur + Pad_Size - 1;
   end Encode;

   function Read_Header (Buf : Byte_Array) return Description
   is
      use type Interfaces.Unsigned_32;
      use type Byte;

      Pos          : Natural := Buf'First;
      Channels_B   : Byte;
      Colorspace_B : Byte;
   begin
      if Buf'Length < Header_Size then
         raise Decode_Error with "Read_Header: truncated header";
      end if;

      for I in Magic'Range loop
         if Buf (Pos) /= Byte (Character'Pos (Magic (I))) then
            raise Decode_Error with "Read_Header: bad magic";
         end if;
         Pos := Pos + 1;
      end loop;

      declare
         Width : constant Interfaces.Unsigned_32 := Read_32 (Buf, Pos);
         Height : constant Interfaces.Unsigned_32 := Read_32 (Buf, Pos);
      begin
         if Width = 0
            or else Height = 0
            or else Height >= Pixels_Max / Width
         then
            raise Decode_Error with "Read_Header: invalid dimensions";
         end if;

         Channels_B := Buf (Pos);
         Pos := Pos + 1;
         Colorspace_B := Buf (Pos);

         if Channels_B not in 3 .. 4 then
            raise Decode_Error with "Read_Header: bad channel count";
         end if;

         if Colorspace_B > 1 then
            raise Decode_Error with "Read_Header: bad colorspace";
         end if;

         return Description'
            (Width      => Width,
             Height     => Height,
             Channels   => Channel_Count (Channels_B),
             Colorspace => Colorspace_Kind'Val (Natural (Colorspace_B)));
      end;
   end Read_Header;

   procedure Decode
      (Buf    : Byte_Array;
       Desc   : out Description;
       Output : out Byte_Array;
       Last   : out Natural)
   is
      use type Interfaces.Unsigned_32;
      use type Byte;

      Pos     : Natural := Buf'First + Header_Size;
      Out_Pos : Natural := Output'First;
      Run     : Natural := 0;
      Px      : Pixel := (R => 0, G => 0, B => 0, A => 255);

      Index : Pixel_Table := (others => Zero_Pixel);

      --  Drop end pad for chunks
      Chunks_Last : constant Natural := Buf'Last - Pad_Size;

      --  Read one byte at Pos and advance
      procedure Get
         (Pos : in out Natural;
          Buf : Byte_Array;
          B   : out Byte)
      is
      begin
         B := Buf (Pos);
         Pos := Pos + 1;
      end Get;
   begin

      --  Read_Header handles (most) of validation
      Desc := Read_Header (Buf);

      declare
         Px_Count : constant Integer :=
            Integer (Desc.Width) * Integer (Desc.Height);
         Stride : constant Integer := Integer (Desc.Channels);
      begin
         if Output'Length < Px_Count * Stride then
            raise Constraint_Error with "Decode: output buffer too small";
         end if;

         --  eat chunks
         for P in 1 .. Px_Count loop
            if Run > 0 then
               Run := Run - 1;
            elsif Pos <= Chunks_Last then
               declare  --  {{{
                  B1 : Byte;
               begin
                  Get (Pos, Buf, B1);

                  --  Full byte tag
                  if B1 = Op_RGB or else B1 = Op_RGBA then
                     Get (Pos, Buf, Px.R);
                     Get (Pos, Buf, Px.G);
                     Get (Pos, Buf, Px.B);
                     if B1 = Op_RGBA then
                        Get (Pos, Buf, Px.A);
                     end if;

                     --  All non-run ops store into the index table
                     Index (Color_Hash (Px)) := Px;

                  else
                     --  Nibble tag
                     case B1 and Mask2 is
                        when Op_Index =>
                           Px := Index (Slot_Index (B1 and 16#3F#));
                        when Op_Diff =>
                           Px.R := Px.R
                              + (Interfaces.Shift_Right (B1, 4)
                              and 16#03#) - 2;
                           Px.G := Px.G
                              + (Interfaces.Shift_Right (B1, 2)
                              and 16#03#) - 2;
                           Px.B := Px.B + (B1 and 16#03#) - 2;
                        when Op_Luma =>
                           declare
                              B2 : Byte;
                              Vg : constant Integer :=
                                 Integer (B1 and 16#3F#) - 32;
                              Vr : Integer;
                              Vb : Integer;
                           begin
                              Get (Pos, Buf, B2);
                              Vr := Integer (Interfaces.Shift_Right
                                 (B2, 4)) - 8;
                              Vb := Integer (B2 and 16#0F#) - 8;
                              Px.R := Byte (Integer (Px.R) + Vg + Vr);
                              Px.G := Byte (Integer (Px.G) + Vg);
                              Px.B := Byte (Integer (Px.B) + Vg + Vb);
                           end;
                        when Op_Run =>
                           Run := Natural (B1 and 16#3F#);
                        when others => null; --  TODO: maybe throw error???
                     end case;

                     --  Runs repeat the previous pixel: no index store
                     if (B1 and Mask2) /= Op_Run then
                        Index (Color_Hash (Px)) := Px;
                     end if;
                  end if;
               end;  --  }}}
            end if;

            --  write px
            Output (Out_Pos)     := Px.R;
            Output (Out_Pos + 1) := Px.G;
            Output (Out_Pos + 2) := Px.B;
            if Desc.Channels = 4 then
               Output (Out_Pos + 3) := Px.A;
            end if;
            Out_Pos := Out_Pos + Stride;
         end loop;

         Last := Out_Pos - 1;
      end;
   end Decode;

end Qoi_Lite;
