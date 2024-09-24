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

const OsTask = @import("source/os_task.zig");
const OsCore = @import("source/os_core.zig");
const TaskQueue = @import("source/util/task_queue.zig");
const builtin = @import("builtin");
const ArchInterface = @import("source/arch/arch_interface.zig");

var arch = ArchInterface.arch;

pub const Mutex = @import("source/os_mutex.zig").Mutex;
pub const Task = OsTask.Task;
pub const OsError = OsCore.Error;
pub const OsConfig = OsCore.OsConfig;

pub fn init() void {
    arch.coreInit();
}

const task_ctrl = &OsTask.task_control;

///Returns a new task.
pub fn create_task(config: OsTask.TaskConfig) TaskQueue.TaskHandle {
    return TaskQueue.TaskHandle{
        .name = config.name,
        ._data = Task.create_task(config),
    };
}

///Adds a task to the operating system.
pub fn addTaskToOs(task: *TaskQueue.TaskHandle) void {
    task_ctrl.addReady(task);
}

export var g_stack_offset: u32 = 0x08;
///The operating system will begin multitasking.  This function never returns.
pub fn startOS(comptime config: OsConfig) void {
    if (OsCore.isOsStarted() == false) {
        comptime {
            if (config.idle_stack_size < OsCore.DEFAULT_IDLE_TASK_SIZE) {
                @compileError("Idle stack size cannont be less than the default size.");
            }
        }

        OsCore.setOsConfig(config);

        var idle_stack: [config.idle_stack_size]u32 = [_]u32{0xDEADC0DE} ** config.idle_stack_size;

        var idle_task = create_task(.{
            .name = "idle task",
            .priority = 0, //Idle task priority is ignored
            .stack = &idle_stack,
            .subroutine = config.idle_task_subroutine,
        });

        task_ctrl.addIdleTask(&idle_task);
        task_ctrl.initAllStacks();

        //Find offset to stack ptr as zig does not guarantee struct field order
        g_stack_offset = @abs(@intFromPtr(&idle_task._data.stack_ptr) -% @intFromPtr(&idle_task));

        OsCore.setOsStarted();
        arch.runScheduler(); //begin os

        if (arch.isDebugAttached()) {
            @breakpoint();
        }

        unreachable;
    }
}

///Put the active task to sleep.  It will become ready to run again `time_ms` milliseconds.
pub fn delay(time_ms: u32) OsCore.Error!void {
    var running_task = try OsCore.validateOsCall();
    const timeout: u32 = (time_ms * OsCore.getOsConfig().system_clock_freq_hz) / 1000;
    arch.criticalStart();
    task_ctrl.removeReady(@volatileCast(running_task));
    task_ctrl.addYeilded(@volatileCast(running_task));
    running_task._data.timeout = timeout;
    running_task._data.state = OsTask.State.yeilded;
    arch.criticalEnd();
    arch.runScheduler();
}
