# Package

version       = "0.0.1"
author        = "dadadani"
description   = "MTProto client written in Nim"
license       = "LGPL-3.0"
srcDir        = "src"


# Dependencies

requires "nim >= 1.2.0"
requires "zippy >= 0.3.13"
requires "nimcrypto >= 0.5.4"
#TODO: Stint is unstable, use a more specific version
requires "stint >= 0.0.1" 
requires "gmp >= 0.2.5"
requires "random >= 0.5.7"
