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

const Task = @import("../../task.zig").Task;
const OsCore = @import("../../os_core.zig");
const Self = @This();

pub var scheduler: bool = false;
pub var contex_switch: bool = false;
pub var int_active: bool = false;
pub var debug_atached: bool = false;
pub var criticalSection: bool = false;

//Test function
pub fn schedulerRan() bool {
    defer scheduler = false;
    return scheduler;
}

pub fn contextSwitchRan() bool {
    defer contex_switch = false;
    return contex_switch;
}

pub fn getCriticalSection() bool {
    return criticalSection;
}

pub fn setDebug(attached: bool) void {
    debug_atached = attached;
}

pub fn setInterruptActive(active: bool) void {
    int_active = active;
}

//Interface
pub const minStackSize = 10;

pub fn coreInit(clock_config: *const OsCore.ClockConfig) void {
    _ = clock_config;
}

pub fn initStack(task: *Task) void {
    _ = task;
}

pub fn interruptActive() bool {
    return int_active;
}

//Enable Interrupts
pub inline fn criticalEnd() void {
    criticalSection = false;
}

//Disable Interrupts
pub inline fn criticalStart() void {
    criticalSection = true;
}

pub inline fn runScheduler() void {
    scheduler = true;
}

pub inline fn runContextSwitch() void {
    contex_switch = true;
}

pub inline fn startOs() void {}

pub inline fn isDebugAttached() bool {
    return debug_atached;
}
