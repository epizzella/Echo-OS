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

const OsTask = @import("../task.zig");
const OsCore = @import("../os_core.zig");
const OsTimer = @import("timer.zig");
const ArchInterface = @import("../arch/arch_interface.zig");

const SyncList = createControlList(SyncContext);
const Error = OsCore.Error;
const task_control = &OsTask.task_control;
const Task = OsTask.Task;
const TaskQueue = OsTask.TaskQueue;
const Timer = OsTimer.Timer;

const Arch = ArchInterface.Arch;

pub const SyncContext = struct {
    _next: ?*SyncContext = null,
    _prev: ?*SyncContext = null,
    _pending: TaskQueue = .{},
    _init: bool = false,
};

pub const SyncControl = struct {
    const Self = @This();
    var objList = SyncList{};

    pub fn add(new: *SyncContext) Error!void {
        try objList.add(new);
    }

    pub fn remove(detach: *SyncContext) Error!void {
        if (detach._pending.head != null) return Error.TaskPendingOnSync;
        try objList.remove(detach);
    }

    /// Update the timeout of all the task pending on the synchronization object
    pub fn updateTimeOut() void {
        var sync_objs = objList.list;
        while (sync_objs) |sync_obj| {
            var opt_task = sync_obj._pending.head;
            while (opt_task) |task| {
                if (task._timeout > 0) { //tasks wait indefinetly when _timeout is set to 0
                    task._timeout -= 1;
                    if (task._timeout == 0) task._SyncContext.timed_out = true;
                    task_control.readyTask(task);
                }

                opt_task = task._to_tail;
            }

            sync_objs = sync_obj._next;
        }
    }

    pub fn blockTask(blocker: *SyncContext, timeout_ms: u32) !void {
        if (task_control.popRunningTask()) |task| {
            blocker._pending.insertSorted(task);
            task._timeout = (timeout_ms * OsCore.getOsConfig().clock_config.os_sys_clock_freq_hz) / 1000;
            task._state = OsTask.State.blocked;
            Arch.criticalEnd();
            Arch.runScheduler();

            if (task._SyncContext.timed_out) {
                task._SyncContext.timed_out = false;
                return Error.TimedOut;
            }
            if (task._SyncContext.aborted) {
                task._SyncContext.aborted = false;
                return Error.Aborted;
            }
        } else {
            return Error.RunningTaskNull;
        }
    }

    pub fn abort(blocker: *SyncContext, task: *Task) Error!void {
        const running_task = try validateCallMinor();
        if (!blocker._init) return Error.Uninitialized;
        const q = task._queue orelse return Error.TaskNotBlockedBySync;
        if (q != &blocker._pending) return Error.TaskNotBlockedBySync;

        Arch.criticalStart();
        defer Arch.criticalEnd();
        task._SyncContext.aborted = true;
        task_control.readyTask(task);
        if (task._priority < running_task._priority) {
            Arch.criticalEnd();
            Arch.runScheduler();
        }
    }
};

const TimerList = createControlList(Timer);

pub const TimerControl = struct {
    const Self = @This();
    var runningList = TimerList{};
    var expiredList = TimerList{};

    pub fn start(timer: *Timer) Error!void {
        try runningList.add(timer);
        timer._state = OsTimer.State.running;
    }

    pub fn stop(timer: *Timer) Error!void {
        try runningList.remove(timer);
        timer._state = OsTimer.State.idle;
    }

    pub fn restart(timer: *Timer) Error!void {
        try expiredList.remove(timer);
        try runningList.add(timer);
        timer._state = OsTimer.State.running;
    }

    pub fn expired(timer: *Timer) Error!void {
        try runningList.remove(timer);
        try expiredList.add(timer);
        timer._state = OsTimer.State.expired;
    }

    pub fn getExpiredList() ?*Timer {
        return expiredList.list;
    }

    /// Update the timeout of all running timers
    pub fn updateTimeOut() void {
        var running_timer = runningList.list;
        while (running_timer) |timer| {
            timer._running_time_ms -= 1;
            if (timer._running_time_ms == 0) {
                expired(timer) catch {
                    @panic("Unable to mark timer as expired");
                };

                OsTimer.timer_sem.post(.{ .runScheduler = false }) catch {
                    @panic("Unable to post timer semaphore.");
                };
            }

            running_timer = timer._next orelse break;
        }
    }
};

fn createControlList(comptime T: type) type {
    comptime {
        if (!(T == Timer or T == SyncContext)) {
            @compileError("Invalid type");
        }
    }

    return struct {
        list: ?*T = null,
        const Self = @This();

        pub fn add(self: *Self, new: *T) Error!void {
            if (new._init) return Error.Reinitialized;
            Arch.criticalStart();
            new._next = self.list;
            if (self.list) |l| {
                l._prev = new;
            }
            self.list = new;
            new._init = true;
            Arch.criticalEnd();
        }

        pub fn remove(self: *Self, detach: *T) Error!void {
            if (!detach._init) return Error.Uninitialized;

            Arch.criticalStart();
            if (self.list == detach) {
                self.list = detach._next;
            }

            if (detach._next) |next| {
                next._prev = detach._prev;
            }

            if (detach._prev) |prev| {
                prev._next = detach._next;
            }

            detach._next = null;
            detach._prev = null;
            detach._init = false;
            Arch.criticalEnd();
        }
    };
}

pub fn validateCallMajor() Error!*Task {
    const running_task = try validateCallMinor();

    if (OsCore.getOsConfig().timer_config.timer_enable and //
        running_task == &OsCore.timer_task and //
        OsTimer.getCallbackExecution())
    {
        return Error.IllegalTimerTask;
    }

    if (running_task._priority == OsTask.IDLE_PRIORITY_LEVEL) return Error.IllegalIdleTask;
    if (Arch.interruptActive()) return Error.IllegalInterruptAccess;
    return running_task;
}

pub fn validateCallMinor() Error!*Task {
    if (!OsCore.isOsStarted()) return Error.OsOffline;
    const running_task = task_control.table[task_control.running_priority].ready_tasks.head orelse return Error.RunningTaskNull;
    return running_task;
}
