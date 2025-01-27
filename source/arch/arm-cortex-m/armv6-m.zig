/////////////////////////////////////////////////////////////////////////////////
// Copyright 2024 Edward Pizzella
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
/////////////////////////////////////////////////////////////////////////////////

pub const minStackSize = 16;
pub const LOWEST_PRIO_MSK: u2 = 0x3;

/////////////////////////////////////////////
//   System Control Register Addresses    //
///////////////////////////////////////////
pub const ACTLR_ADDRESS: u32 = 0xE000E008; // Auxiliary Control Register

//SysTic Timer is optional on armv6-m
pub const SYST_CSR_ADDRESS: u32 = 0xE000E010; //   SysTick Control and Status Register
pub const SYST_RVR_ADDRESS: u32 = 0xE000E014; //   SysTick Reload Value Register
pub const SYST_CVR_ADDRESS: u32 = 0xE000E018; //   SysTick Current Value Register
pub const SYST_CALIB_ADDRESS: u32 = 0xE000E01C; // SysTick Calibration Value Register (Implementation specific)

pub const CPUID_ADDRESS: u32 = 0xE000ED00; // CPUID Base Register
pub const ICSR_ADDRESS: u32 = 0xE000ED04; //  Interrupt Control and State Register (RW or RO)
pub const VTOR_ADDRESS: u32 = 0xE000ED08; //  Vector Table Offset Register
pub const AIRCR_ADDRESS: u32 = 0xE000ED0C; // Application Interrupt and Reset Control Register
pub const SCR_ADDRESS: u32 = 0xE000ED10; //   System Control Register
pub const CCR_ADDRESS: u32 = 0xE000ED14; //   Configuration and Control Register
pub const SHPR2_ADDRESS: u32 = 0xE000ED1C; // System Handler Priority Register 2
pub const SHPR3_ADDRESS: u32 = 0xE000ED20; // System Handler Priority Register 3
pub const SHCSR_ADDRESS: u32 = 0xE000ED24; // System Handler Control and State Register
pub const DFSR_ADDRESS: u32 = 0xE000ED30; //  Debug Fault Status Register

//System Debug Registers
pub const DHCSR_ADDRESS: u32 = 0xE000EDF0; // Halting Control and Status Register
pub const DCRSR_ADDRESS: u32 = 0xE000EDF4; // Core Register Selector Register
pub const DCRDR_ADDRESS: u32 = 0xE000EDF8; // Core Register Data Register
pub const DEMCR_ADDRESS: u32 = 0xE000EDFC; // Exception and Monitor Control Register

/////////////////////////////////////////////
//    System Control Register Structs     //
///////////////////////////////////////////

///SysTick Control and Status Register
pub const SYST_CSR_REG = packed struct {
    /// RW - Indicates if the SysTick counter is enabled
    ENABLE: bool,
    /// RW - Indicates if counting to 0 causes the SysTick exception to pend.
    /// False: Count to 0 does not affect the SysTick exception status
    /// True: Count to 0 changes the SysTick exception status to pending.
    TICKINT: bool,
    /// RW - Indicates the SysTick clock source:
    /// 0 = SysTick uses the IMPLEMENTATION DEFINED external reference clock.
    /// 1 = SysTick uses the processor clock.
    /// If no external clock is provided, this bit reads as 1 and ignores writes.
    CLKSOURCE: u1,
    /// Reserved
    RESERVED_3_15: u13,
    /// Indicates whether the counter has counted to 0 since the last read of this register
    /// False = Timer has not counted to 0.
    /// True = Timer has counted to 0.
    COUNTFLAG: bool,
    RESERVED_17_31: u15,
    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

///SysTick Reload Value Register
const SYST_RVR_REG = packed struct {
    /// RW - The value to load into the SYST_CVR when the counter reaches 0.
    RELOAD: u24,
    ///Reserved
    RESERVED_24_31: u8,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

/// Vector Table Offset Register
pub const VTOR_REG = packed struct {
    /// Reserved
    RESERVED_0_6: u7,
    /// RW - Bits 31-7 of the vector table address
    TBLOFF: u25,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

///Interrupt Control State Register
pub const ICSR_REG = packed struct {
    /// RO - Current executing exception's number. A value of 0 = Thread mode
    VECTACTIVE: u9,
    RESERVED_9_11: u3,
    /// RO - Highest priority pending enabled execption's number
    VECTPENDING: u9,
    RESERVED_21: u1,
    /// RO - Extneral interrrupt pending
    ISRPENDING: bool,
    /// RO - Service pending execption on on exit from debug halt
    ISRPREEMPT: bool,
    RESERVED_24: u1,
    /// WO - 0 = No effect; 1 = Clear SysTick pending status
    PENDSTCLR: bool,
    /// WR - Write: sets SysTick exception pending. Reads: indicates state of SysTick exception
    PENDSTSET: bool,
    /// WO - 0 = No effect; 1 = Clear PendSV pending status
    PENDSVCLR: bool,
    /// WR - Write: sets PendSV exception pending. Reads: indicates state of PendSV exception
    PENDSVSET: bool,
    RESERVED_29_30: u2,
    /// RW - Write: sets NMI exception pending. Reads: indicates state of NMI exception
    NMIPENDSET: bool,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

///System Handler Priority Register 2
pub const SHPR2_REG = packed struct {
    RESERVED_0_7: u8,
    RESERVED_8_15: u8,
    RESERVED_16_23: u8,
    /// RW - Systme Handler 11 Priority: Debug Monitor
    PRI_SVC: u8,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

///System Handler Priority Register 3
pub const SHPR3_REG = packed struct {
    RESERVED_0_21: u22,
    /// RW - System Handler 14 Priority: Pend_SV
    PRI_PENDSV: u2,
    RESERVED_24_29: u6,
    /// RW - System Handler 15 Priority: SystTick
    PRI_SYSTICK: u2,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};

///Debug Halting Control and Status Register
pub const DHCSR_REG = packed struct {
    /// RO - 0 = No debugger attached; 1 = Debugger attached
    C_DEBUGEN: bool,
    /// RW - 0 = Request processor run; 1 = Request processor halt
    C_HALT: bool,
    /// RW - 0 = Single step disable; 1 = Single step enabled
    C_STEP: bool,
    /// RW - 0 = Do not Mask; 1 = Mask PendSV, SysTick, & external interrupts
    C_MASKINTS: bool,
    RESERVED_4_15: u12,
    ///Debug key. Write 0xA05F to this field to enable write accesses to bits[15:0]
    DBGKEY: u16,

    comptime {
        if (@bitSizeOf(@This()) != @bitSizeOf(u32)) @compileError("Register struct must be must be 32 bits");
    }
};
