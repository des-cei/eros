// Copyright 2024 CEI

#ifndef _CB_SAFETY_Config_H_
#define _CB_SAFETY_Config_H_

//Todo: Check if __cplusplus this is necesary
#ifdef __cplusplus
extern "C" {
#endif

#ifdef __cplusplus
}
#endif

#define CRITICAL_SECTION 	0x1
#define NONE_CRITICAL_SECTION	0x0

                                //HOT-BIT
#define MASTER_CORE0	0x1	//0b001
#define MASTER_CORE1	0x2	//0b010
#define MASTER_CORE2	0x4	//0b100

#define CORE01_MASK     0x3 //0b011
#define CORE02_MASK     0x5 //0b101
#define CORE12_MASK     0x6 //0b110

#define SINGLE_MODE     0x0
#define TMR_MODE        0x1
#define DMR_MODE        0x2
#define LOCKSTEP_MODE   0x3

#define START           0x1 

#endif  
