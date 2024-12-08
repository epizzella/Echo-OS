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

const OsTask = @import("../../task.zig");
const OsCore = @import("../../os_core.zig");

pub const minStackSize = if (builtin.abi == std.Target.Abi.eabi) 17 else 48;
pub const LOWEST_PRIO_MSK: u8 = 0xFF;

pub inline fn contextSwitch() void {
    //context switch here
    OsTask.TaskControl.current_task.?._state = OsTask.State.running;
}
