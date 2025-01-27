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

const OsTask = @import("task.zig");
const Mutex = @import("synchronization/mutex.zig");
const Semaphore = @import("synchronization/semaphore.zig");
const EventGroup = @import("synchronization/event_group.zig");
const ArchInterface = @import("arch/arch_interface.zig");
const OsSyncControl = @import("synchronization/sync_control.zig");
const OsTimer = @import("synchronization/timer.zig");
const builtin = @import("builtin");

pub const Task = OsTask.Task;

const Arch = ArchInterface.Arch;
const task_ctrl = &OsTask.task_control;
const SyncControl = OsSyncControl.SyncControl;
const TimerControl = OsSyncControl.TimerControl;

pub const DEFAULT_IDLE_TASK_SIZE = Arch.minStackSize;

var os_config: OsConfig = undefined;

pub fn getOsConfig() OsConfig {
    return os_config;
}

pub fn setOsConfig(config: OsConfig) void {
    if (!os_started) {
        os_config = config;
    }
}

fn idle_subroutine() !void {
    while (true) {}
}

pub const OsConfig = struct {
    /// OS & CPU clock Configuration
    clock_config: ClockConfig,
    /// Idle Task Configuration
    idle_task_config: IdleTaskConfig = .{},
    /// Function to execute at the beginning of the sysTick interrupt;
    os_tick_callback: ?*const fn () void = null,
    /// Software Timer Configuration
    timer_config: TimerConfig = .{},
};

pub const IdleTaskConfig = struct {
    /// Subroutine executed by the idle task. Replaces the default idle task.  This subroutine cannot be suspended or blocked;
    idle_task_subroutine: *const fn () anyerror!void = &idle_subroutine,
    /// Number of words in the idle task stack.   Note:  if idle_task_subroutine is provided idle_stack_size must be
    /// larger than DEFAULT_IDLE_TASK_SIZE;
    idle_stack_size: usize = DEFAULT_IDLE_TASK_SIZE,
};

pub const ClockConfig = struct {
    /// The frequency of the OS system clock in hz.
    os_sys_clock_freq_hz: u32,
    ///The frequency of the CPU clock in hz
    cpu_clock_freq_hz: u32,
};

pub const TimerConfig = struct {
    timer_enable: bool = false,
    timer_task_priority: u5 = 0,
    timer_stack_size: usize = 0,
};

var os_started: bool = false;
pub fn setOsStarted() void {
    os_started = true;
}

/// Returns true when the OS is running
pub fn isOsStarted() bool {
    return os_started;
}

pub export var g_stack_offset: usize = 0x08;

pub var timer_task: Task = undefined;

/// Start Multitasking
pub inline fn startOS(comptime config: OsConfig) void {
    const iss = config.idle_task_config.idle_stack_size;
    if (isOsStarted() == false) {
        comptime {
            if (iss < DEFAULT_IDLE_TASK_SIZE) {
                @compileError("Idle stack size cannont be less than the default size.");
            }
        }

        setOsConfig(config);

        Arch.coreInit(&config.clock_config);

        var idle_stack: [iss]u32 = [_]u32{0xDEADC0DE} ** iss;
        var idle_task = Task.create_task(.{
            .name = "idle task",
            .priority = 0, //Idle task priority is ignored
            .stack = &idle_stack,
            .subroutine = config.idle_task_config.idle_task_subroutine,
        });

        task_ctrl.addIdleTask(&idle_task);

        var timer_stack: [config.timer_config.timer_stack_size]u32 = undefined;

        if (config.timer_config.timer_enable) {
            comptime {
                if (config.timer_config.timer_stack_size < DEFAULT_IDLE_TASK_SIZE) {
                    @compileError("Timer stack size cannont be less than the default size.");
                }
            }
            timer_stack = [_]u32{0xDEADC0DE} ** config.timer_config.timer_stack_size;
            timer_task = Task.create_task(.{
                .name = "timer task",
                .priority = config.timer_config.timer_task_priority,
                .stack = &timer_stack,
                .subroutine = OsTimer.timerSubroutine,
            });

            timer_task.init();
            OsTimer.timer_sem.init() catch unreachable;
        }

        //Find offset to stack ptr as zig does not guarantee struct field order
        g_stack_offset = @abs(@intFromPtr(&idle_task._stack_ptr) -% @intFromPtr(&idle_task));

        setOsStarted();
        Arch.runScheduler(); //begin os

        if (Arch.isDebugAttached()) {
            // Os failed to start.  Likely something CPU specific is configured incorrectly.
            @breakpoint();
        }

        if (!builtin.is_test) unreachable;
    }
}

/// Schedule the next task to run
pub fn schedule() void {
    task_ctrl.setNextRunningTask();
    if (task_ctrl.validSwitch()) {
        Arch.runContextSwitch();
    }
}

pub const SyncContext = struct {
    //Event context
    pending_event: usize = 0,
    triggering_event: usize = 0,
    trigger_type: EventTrigger = EventTrigger.all_set,
    //Common Sync Context
    aborted: bool = false,
    timed_out: bool = false,

    pub const EventTrigger = enum {
        all_set,
        all_clear,
        any_set,
        any_clear,
    };
};

/// System tick counter
var ticks: u64 = 0;

pub const Time = struct {
    const math = @import("std").math;

    /// Get the current number of elapsed ticks
    pub fn getTicks() u64 {
        return ticks;
    }

    /// Get the current number of elapsed ticks as milliseconds (rounded down)
    pub fn getTicksMs() u64 {
        return (ticks * 1000) / os_config.clock_config.os_sys_clock_freq_hz;
    }

    /// Put the active task to sleep.  It will become ready to run again after `time_ms` milliseconds.
    /// * `time_ms` when converted to system ticks cannot exceed 2^32 system ticks.
    pub fn delay(time_ms: u32) Error!void {
        var running_task = try validateCall();
        if (time_ms != 0) {
            var timeout: u32 = math.mul(u32, time_ms, os_config.clock_config.os_sys_clock_freq_hz) catch return Error.SleepDurationOutOfRange;
            timeout /= 1000;
            Arch.criticalStart();
            task_ctrl.yeildTask(running_task);
            running_task._timeout = timeout;
            Arch.criticalEnd();
            Arch.runScheduler();
        }
    }

    pub const SleepTime = struct {
        ms: usize = 0,
        sec: usize = 0,
        min: usize = 0,
        hr: usize = 0,
        days: usize = 0,
    };

    fn sleepTimeToMs(time: *SleepTime) !u32 {
        var total_ms = time.ms;
        var temp_ms = try math.mul(u32, time.sec, 1000);
        total_ms = try math.add(u32, total_ms, temp_ms);
        temp_ms = try math.mul(u32, time.min, 60_000);
        total_ms = try math.add(u32, total_ms, temp_ms);
        temp_ms = try math.mul(u32, time.hr, 3_600_000);
        total_ms = try math.add(u32, total_ms, temp_ms);
        temp_ms = try math.mul(u32, time.hr, 86_400_000);
        total_ms = try math.add(u32, total_ms, temp_ms);
        return total_ms;
    }

    /// Put the active task to sleep.  The value of `time` must be less than 2^32 milliseconds (~49.7 days) and less than 2^32 system ticks.
    pub fn sleep(time: SleepTime) Error!void {
        const timeout = sleepTimeToMs(&time) catch return Error.SleepDurationOutOfRange;
        try delay(timeout);
    }

    fn validateCall() Error!*Task {
        if (!os_started) return Error.OsOffline;
        const running_task = task_ctrl.table[task_ctrl.running_priority].ready_tasks.head orelse return Error.RunningTaskNull;

        if (getOsConfig().timer_config.timer_enable and //
            running_task == &timer_task and //
            OsTimer.getCallbackExecution())
        {
            return Error.IllegalTimerTask;
        }

        if (running_task._priority == OsTask.IDLE_PRIORITY_LEVEL) return Error.IllegalIdleTask;
        if (Arch.interruptActive()) return Error.IllegalInterruptAccess;
        return running_task;
    }
};

///System tick functionality.  Should be called from the System Clock interrupt. e.g. SysTick_Handler
pub inline fn OsTick() void {
    if (os_config.os_tick_callback) |callback| {
        callback();
    }

    if (os_started) {
        ticks +%= 1;
        SyncControl.updateTimeOut();
        TimerControl.updateTimeOut();
        task_ctrl.updateDelayedTasks();
        task_ctrl.cycleActive();
        schedule();
    }
}

pub const Error = error{
    /// The running task is null.  This is an illegal state once multi tasking as started.
    RunningTaskNull,
    /// The operating system has not started multi tasking.
    OsOffline,
    /// Illegal call from idle task
    IllegalIdleTask,
    /// Illegal call from timer task
    IllegalTimerTask,
    /// Illegal call from interrupt
    IllegalInterruptAccess,
    /// A task that does not own this mutex attempted release
    InvalidMutexOwner,
    ///The task that owns this mutex attempted to aquire it a second time
    MutexOwnerAquire,
    /// Time out limit reached.
    TimedOut,
    /// Function manually aborted
    Aborted,
    /// Os Object not initalized
    Uninitialized,
    /// Os Object already initalized
    Reinitialized,
    /// The task is not blocked by the synchonization object
    TaskNotBlockedBySync,
    /// The synchonization object cannot be deleted because there is atleast 1 task pending on it.
    TaskPendingOnSync,
    /// The amount of time specified for the task to sleep exceeds the max value of 2^32 ms
    SleepDurationOutOfRange,
    /// Task cannot be resumed as it is not suspended
    IllegalTaskResume,
};
