// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module MaterializedMovieQuery {
  pure def place(n:int):int = range(0,n).foldl(1,(v,_) => v*2)
  pure def bit(id:int,n:int):bool = id/place(n)%2 == 1
  pure def cast(id:int,f:int,a:int):bool = bit(id%256,f*3+a) and not(id/256 == 1 and f == 1 and a == 1)
  pure def eligible(id:int,f:int,a:int):bool = cast(id,f,a) and bit(id%256,6+f)
  pure def coactor(id:int,f:int,a:int):bool = cast(id,f,0) and cast(id,f,a)
  pure def left(id:int,m:int,a:int):bool = eligible(id,1,a) and (m%3 == 2 or a != 0)
  pure def right(id:int,m:int,a:int):bool = (coactor(id,0,a) or coactor(id,1,a)) and (m%3 != 1 or a != 0)
  pure def answer(id:int,m:int,a:int):bool = if (m/3 == 0) left(id,m,a) and right(id,m,a) else left(id,m,a) or right(id,m,a)
  pure def mask(n:int,p:int => bool):int = range(0,n).foldl(0,(v,i) => if (p(i)) v+place(i) else v)
  pure val conformance = range(0,3072).foldl(List(),(rows,n) => {
    val id = n/6
    val m = n%6
    rows.append(List(n,mask(6,p => eligible(id,p/3,p%3)),mask(6,p => coactor(id,p/3,p%3)),mask(3,a => answer(id,m,a))))
  })
}
