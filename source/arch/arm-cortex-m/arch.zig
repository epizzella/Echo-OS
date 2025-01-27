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

const std = @import("std");
const cpu = std.Target.arm.cpu;
const builtin = @import("builtin");

const OsTask = @import("../../task.zig");
const OsCore = @import("../../os_core.zig");
const Os = @import("../../../os.zig");

const V6 = @import("armv6-m.zig");
const V7 = @import("armv7-m.zig");
const V8 = @import("armv8-m.zig");
const V8P1 = @import("armv8.1-m.zig");

const core = getCore: {
    const cpu_model = builtin.cpu.model.*;

    if (std.meta.eql(cpu_model, cpu.cortex_m0) or //
        std.meta.eql(cpu_model, cpu.cortex_m0plus))
    {
        break :getCore V6;
    } else if (std.meta.eql(cpu_model, cpu.cortex_m3) or //
        std.meta.eql(cpu_model, cpu.cortex_m4) or //
        std.meta.eql(cpu_model, cpu.cortex_m7))
    {
        break :getCore V7;
    } else {
        @compileError("Unsupported architecture selected.");
    }
};

const task_ctrl = &OsTask.task_control;
const Task = OsTask.Task;

pub const Self = @This();

/////////////////////////////////////////////////////////
//    Architecture specific Function Implemntations   //
///////////////////////////////////////////////////////
pub const minStackSize = core.minStackSize;

const Error = error{
    SysTickAddressInvalid,
    SvcAddressInvalid,
    PendSvAddressInvalid,
};

//NVIC table offsets
const systick_offset = 0x3c;
const svc_offset = 0x2c;
const pendsv_offset = 0x38;

pub fn coreInit(clock_config: *const OsCore.ClockConfig) void {
    const systick_address: u32 = @intFromPtr(&SysTick_Handler);
    const svc_address: u32 = @intFromPtr(&SVC_Handler);
    const pendsv_address: u32 = @intFromPtr(&PendSV_Handler);

    const vtor_reg: *u32 = @ptrFromInt(core.VTOR_ADDRESS);
    const vector_table_address = vtor_reg.*;

    //Addresses of the NVIC table that store exception handler pointers.
    const nvic_systick: *u32 = @ptrFromInt(vector_table_address + systick_offset);
    const nvic_svc: *u32 = @ptrFromInt(vector_table_address + svc_offset);
    const nvic_pendsv: *u32 = @ptrFromInt(vector_table_address + pendsv_offset);

    //Exception Handler addresses stored in the NVIC table.
    const nvic_systick_address = nvic_systick.*;
    const nvic_svc_address = nvic_svc.*;
    const nvic_pendsv_address = nvic_pendsv.*;

    //Panic if exceptions are not setup correctly
    if (systick_address != nvic_systick_address) {
        @panic("SysTick Handler address in NVIC table does not match SysTick_Handler() address.\n");
    }

    if (svc_address != nvic_svc_address) {
        @panic("SVC Handler address in NVIC table does not match SVC_Handler() address.\n");
    }

    if (pendsv_address != nvic_pendsv_address) {
        @panic("PendSV Handler address in NVIC table does not match PendSV_Handler() address.\n");
    }

    SHPR3.PRI_PENDSV = core.LOWEST_PRIO_MSK; //Set the pendsv to the lowest priority to tail chain ISRs
    SHPR3.PRI_SYSTICK = ~core.LOWEST_PRIO_MSK; //Set sysTick to the highest priority.

    //Set SysTick reload value
    const ticks: u32 = (clock_config.cpu_clock_freq_hz / clock_config.os_sys_clock_freq_hz) - 1;
    SYST_RVR.RELOAD = @intCast(ticks);

    //Enable SysTick counter & interrupt
    SYST_CSR.CLKSOURCE = 1; //TODO: Make this configurable some how
    SYST_CSR.ENABLE = true;
    SYST_CSR.TICKINT = true;
}

pub fn initStack(task: *Task) void {
    task._stack_ptr = @intFromPtr(&task._stack.ptr[task._stack.len - minStackSize]);
    task._stack.ptr[task._stack.len - 1] = 0x1 << 24; // xPSR
    task._stack.ptr[task._stack.len - 2] = @intFromPtr(&OsTask.taskTopRoutine); // PC
    task._stack.ptr[task._stack.len - 3] = 0x14141414; // LR (R14)
    task._stack.ptr[task._stack.len - 4] = 0x12121212; // R12
    task._stack.ptr[task._stack.len - 5] = 0x03030303; // R3
    task._stack.ptr[task._stack.len - 6] = 0x02020202; // R2
    task._stack.ptr[task._stack.len - 7] = 0x01010101; // R1
    task._stack.ptr[task._stack.len - 8] = 0x00000000; // R0
    task._stack.ptr[task._stack.len - 9] = 0xFFFFFFFD; // EXEC_RETURN (LR)

    //These registers are push/poped via context switch code
    task._stack.ptr[task._stack.len - 10] = 0x11111111; // R11
    task._stack.ptr[task._stack.len - 11] = 0x10101010; // R10
    task._stack.ptr[task._stack.len - 12] = 0x09090909; // R9
    task._stack.ptr[task._stack.len - 13] = 0x08080808; // R8
    task._stack.ptr[task._stack.len - 14] = 0x07070707; // R7
    task._stack.ptr[task._stack.len - 14] = 0x06060606; // R6
    task._stack.ptr[task._stack.len - 14] = 0x05050505; // R5
    task._stack.ptr[task._stack.len - 14] = 0x04040404; // R4
}

pub fn interruptActive() bool {
    return ICSR.VECTACTIVE > 0;
}

///Enable Interrupts
pub inline fn criticalEnd() void {
    asm volatile ("CPSIE    I");
}

///Disable Interrupts
pub inline fn criticalStart() void {
    asm volatile ("CPSID    I");
}

pub inline fn runScheduler() void {
    asm volatile ("SVC    #0");
}

pub inline fn runContextSwitch() void {
    OsTask.TaskControl.next_task._state = .running;
    ICSR.PENDSVSET = true;
}

pub inline fn startOs() void {
    // firstContextSwitch();
}

pub inline fn isDebugAttached() bool {
    return DHCSR.C_DEBUGEN;
}

/////////////////////////////////////////////
//         Exception Handlers             //
///////////////////////////////////////////

export fn SysTick_Handler() void {
    criticalStart();
    OsCore.OsTick();
    criticalEnd();
}

export fn SVC_Handler() void {
    criticalStart();
    OsCore.schedule();
    criticalEnd();
}

extern fn PendSV_Handler() void;

/////////////////////////////////////////////
//        System Control Registers        //
///////////////////////////////////////////
const ICSR: *volatile core.ICSR_REG = @ptrFromInt(core.ICSR_ADDRESS);
const SHPR2: *volatile core.SHPR2_REG = @ptrFromInt(core.SHPR2_ADDRESS);
const SHPR3: *volatile core.SHPR3_REG = @ptrFromInt(core.SHPR3_ADDRESS);
const DHCSR: *volatile core.DHCSR_REG = @ptrFromInt(core.DHCSR_ADDRESS);
const SYST_CSR: *volatile core.SYST_CSR_REG = @ptrFromInt(core.SYST_CSR_ADDRESS);
const SYST_RVR: *volatile core.SYST_RVR_REG = @ptrFromInt(core.SYST_RVR_ADDRESS);
