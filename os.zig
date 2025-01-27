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
const builtin = @import("builtin");

const OsCore = @import("source/os_core.zig");
const OsTask = @import("source/task.zig");
const ArchInterface = @import("source/arch/arch_interface.zig");

const Arch = ArchInterface.Arch;

pub const Task = OsTask.Task;
pub const EventGroup = @import("source/synchronization/event_group.zig").EventGroup;
pub const Mutex = @import("source/synchronization/mutex.zig").Mutex;
pub const Semaphore = @import("source/synchronization/semaphore.zig").Semaphore;
pub const Timer = @import("source/synchronization/timer.zig").Timer;
pub const createMsgQueueType = @import("source/synchronization/msg_queue.zig").createMsgQueueType;
pub const Time = OsCore.Time;
pub const Error = OsCore.Error;
pub const OsConfig = OsCore.OsConfig;

/// The operating system will begin multitasking. This function should only be
/// called once.  Subsequent calls have no effect. The frist time this function
/// is called it will not return as multitasking has started.
pub fn startOS(comptime config: OsConfig) void {
    OsCore.startOS(config);
}

//Disable all interrupts
pub inline fn criticalStart() void {
    Arch.criticalStart();
}

//Enable all interrupts
pub inline fn criticalEnd() void {
    Arch.criticalEnd();
}
