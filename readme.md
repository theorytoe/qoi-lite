# qoi_lite

work in progress pure-ada qoi encode/decode library based
on the QOI reference implementation.

## api

```ada
--  Encode Flat Byte Array into QOI image Byte Array
procedure Encode
  (Buf    : Byte_Array;
   Desc   : Description;
   Output : out Byte_Array;
   Last   : out Natural);

--  Decode QOI Byte Array into Raw Pixel Byte Array
procedure Decode
  (Buf    : Byte_Array;
   Desc   : out Description;
   Output : out Byte_Array;
   Last   : out Natural);


--  Pixel Type
type Pixel is record
  R, G, B, A : Byte := 0;
end record
 with Size => 32;
```

## build/test

	# build
	alr build

	# run tests
	alr test
