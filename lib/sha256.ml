let digest text =
  let open Int32 in
  let k = Array.map of_string [|
    "0x428a2f98";"0x71374491";"0xb5c0fbcf";"0xe9b5dba5";"0x3956c25b";"0x59f111f1";"0x923f82a4";"0xab1c5ed5";
    "0xd807aa98";"0x12835b01";"0x243185be";"0x550c7dc3";"0x72be5d74";"0x80deb1fe";"0x9bdc06a7";"0xc19bf174";
    "0xe49b69c1";"0xefbe4786";"0x0fc19dc6";"0x240ca1cc";"0x2de92c6f";"0x4a7484aa";"0x5cb0a9dc";"0x76f988da";
    "0x983e5152";"0xa831c66d";"0xb00327c8";"0xbf597fc7";"0xc6e00bf3";"0xd5a79147";"0x06ca6351";"0x14292967";
    "0x27b70a85";"0x2e1b2138";"0x4d2c6dfc";"0x53380d13";"0x650a7354";"0x766a0abb";"0x81c2c92e";"0x92722c85";
    "0xa2bfe8a1";"0xa81a664b";"0xc24b8b70";"0xc76c51a3";"0xd192e819";"0xd6990624";"0xf40e3585";"0x106aa070";
    "0x19a4c116";"0x1e376c08";"0x2748774c";"0x34b0bcb5";"0x391c0cb3";"0x4ed8aa4a";"0x5b9cca4f";"0x682e6ff3";
    "0x748f82ee";"0x78a5636f";"0x84c87814";"0x8cc70208";"0x90befffa";"0xa4506ceb";"0xbef9a3f7";"0xc67178f2" |] in
  let h = Array.map of_string [|"0x6a09e667";"0xbb67ae85";"0x3c6ef372";"0xa54ff53a";"0x510e527f";"0x9b05688c";"0x1f83d9ab";"0x5be0cd19"|] in
  let rotate x n = logor (shift_right_logical x n) (shift_left x (32-n)) in
  let xor3 a b c = logxor a (logxor b c) in
  let size = String.length text in
  let padded = ((size+9+63)/64)*64 in
  let bytes = Bytes.make padded '\000' in
  Bytes.blit_string text 0 bytes 0 size; Bytes.set bytes size '\128';
  let bits = Int64.mul (Int64.of_int size) 8L in
  for i = 0 to 7 do Bytes.set bytes (padded-1-i) (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bits (8*i)) 255L))) done;
  let word offset = let v = ref zero in for i = 0 to 3 do v := logor (shift_left !v 8) (of_int (Char.code (Bytes.get bytes (offset+i)))) done; !v in
  for block = 0 to (padded/64)-1 do
    let w = Array.make 64 zero in
    for i = 0 to 15 do w.(i) <- word (block*64+i*4) done;
    for i = 16 to 63 do
      let x = w.(i-15) and y = w.(i-2) in
      let s0 = xor3 (rotate x 7) (rotate x 18) (shift_right_logical x 3) in
      let s1 = xor3 (rotate y 17) (rotate y 19) (shift_right_logical y 10) in
      w.(i) <- add (add w.(i-16) s0) (add w.(i-7) s1)
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3)
    and e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and z = ref h.(7) in
    for i = 0 to 63 do
      let s1 = xor3 (rotate !e 6) (rotate !e 11) (rotate !e 25) in
      let ch = logxor (logand !e !f) (logand (lognot !e) !g) in
      let t1 = add (add (add (add !z s1) ch) k.(i)) w.(i) in
      let s0 = xor3 (rotate !a 2) (rotate !a 13) (rotate !a 22) in
      let maj = xor3 (logand !a !b) (logand !a !c) (logand !b !c) in
      let t2 = add s0 maj in
      z := !g; g := !f; f := !e; e := add !d t1; d := !c; c := !b; b := !a; a := add t1 t2
    done;
    Array.iteri (fun i v -> h.(i) <- add h.(i) v) [|!a;!b;!c;!d;!e;!f;!g;!z|]
  done;
  String.concat "" (Array.to_list (Array.map (Printf.sprintf "%08lx") h))
