// Copyright 2025 CEI UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Luis Waucquez (luis.waucquez.jimenez@upm.es)

#ifndef _BASE_ADDRESS_DEFS_
#define _BASE_ADDRESS_DEFS_

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __cplusplus
}  // extern "C"
#endif
#endif 

//Define
#define GLOBAL_BASE_ADDRESS 0xF0000000	/*User defined*/


//Priv Reg
#define PRIVATE_REG_BASEADDRESS 0x00000000 | GLOBAL_BASE_ADDRESS

//Priv Reg
#define SAFE_WRAPPER_CTRL_BASEADDRESS    (0x00012000 | GLOBAL_BASE_ADDRESS)

//Debug BOOT ADDRESS
#define BOOT_DEBUG_ROM_BASEADDRESS (0x00010000 | GLOBAL_BASE_ADDRESS)

#define BOOT_OFFSET     (BOOT_DEBUG_ROM_BASEADDRESS | 0x0)
#define DEBUG_OFFSET    (BOOT_DEBUG_ROM_BASEADDRESS | 0x50)