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
const SyncControl = @import("sync_control.zig");
const OsSemaphore = @import("semaphore.zig");
const ArchInterface = @import("../arch/arch_interface.zig");
const Semaphore = OsSemaphore.Semaphore;
const Arch = ArchInterface.Arch;

const Task = OsTask.Task;

pub const State = enum { running, expired, idle };

pub const CreateOptions = struct {
    name: []const u8,
    callback: *const fn () void,
};

pub const SetOptions = struct {
    timeout_ms: u32,
    autoreload: bool = false,
    callback: ?*const fn () void = null,
};

const CallbackArgs = struct {};

pub const Timer = struct {
    const Self = @This();

    _name: []const u8,
    _timeout_ms: u32 = 0,
    _running_time_ms: u32 = 0,
    _callback: *const fn () void,
    _state: State = State.idle,
    _autoreload: bool = false,
    _next: ?*Timer = null,
    _prev: ?*Timer = null,
    _init: bool = false,

    pub fn create(options: CreateOptions) Self {
        return Self{
            ._name = options.name,
            ._callback = options.callback,
            ._state = State.idle,
        };
    }

    pub fn set(self: *Self, options: SetOptions) Error!void {
        if (self._state != State.idle) return Error.TimerRunning;

        self._timeout_ms = options.timeout_ms;
        self._running_time_ms = options.timeout_ms;
        self._autoreload = options.autoreload;
        self._callback = options.callback orelse return;
    }

    pub fn start(self: *Self) Error!void {
        if (self._timeout_ms == 0) return Error.TimeoutCannotBeZero;
        if (self._state != State.idle) return Error.TimerRunning;

        try TimerControl.start(self);
    }

    pub fn restart(self: *Self) Error!void {
        if (self._timeout_ms == 0) return Error.TimeoutCannotBeZero;
        self._running_time_ms = self._timeout_ms;
    }

    pub fn cancel(self: *Self) Error!void {
        if (self._state != State.running) return Error.TimerNotRunning;
        try TimerControl.stop(self);
    }

    pub fn getRemainingTime(self: *Self) u32 {
        return self._running_time_ms;
    }

    pub fn getTimerState(self: *Self) State {
        return self._state;
    }
};

pub var timer_sem = Semaphore.create_semaphore(.{ .name = "Timer Semaphore", .inital_value = 0 });

var callback_execution = false;
pub fn timerSubroutine() !void {
    while (true) {
        callback_execution = false;
        try timer_sem.wait(.{});
        callback_execution = true;

        var timer = TimerControl.getExpiredList() orelse continue;
        timer._callback();
        if (timer._autoreload) {
            timer._running_time_ms = timer._timeout_ms;
            try TimerControl.restart(timer);
        } else {
            try TimerControl.stop(timer);
        }
    }
}

pub fn getCallbackExecution() bool {
    return callback_execution;
}

const Error = TmrError || OsError;

const TmrError = error{
    TimeoutCannotBeZero,
    TimerRunning,
    TimerNotRunning,
};

const OsError = OsCore.Error;

pub const TimerControl = struct {
    const Self = @This();
    var _runningList: TimerControlList = .{};
    var _expiredList: TimerControlList = .{};

    pub fn start(timer: *Timer) Error!void {
        try _runningList.add(timer);
        timer._state = State.running;
    }

    pub fn stop(timer: *Timer) Error!void {
        try _runningList.remove(timer);
        timer._state = State.idle;
    }

    pub fn restart(timer: *Timer) Error!void {
        try _expiredList.remove(timer);
        try _runningList.add(timer);
        timer._state = State.running;
    }

    pub fn expired(timer: *Timer) Error!void {
        try _runningList.remove(timer);
        try _expiredList.add(timer);
        timer._state = State.expired;
    }

    pub fn getExpiredList() ?*Timer {
        return _expiredList.list;
    }

    /// Update the timeout of all running timers
    pub fn updateTimeOut() void {
        var running_timer = _runningList.list;
        while (running_timer) |timer| {
            timer._running_time_ms -= 1;
            if (timer._running_time_ms == 0) {
                expired(timer) catch {
                    @panic("Unable to mark timer as expired");
                };

                timer_sem.post(.{ .runScheduler = false }) catch {
                    @panic("Unable to post timer semaphore.");
                };
            }

            running_timer = timer._next;
        }
    }
};

const TimerControlList = struct {
    const Self = @This();
    list: ?*Timer = null,

    //Sorted insert for timers based on timeout
    pub fn add(self: *Self, new: *Timer) Error!void {
        if (new._init) return Error.Reinitialized;
        Arch.criticalStart();
        defer Arch.criticalEnd();

        if (self.list == null) {
            self.list = new;
        } else {
            var timer = self.list;
            while (timer) |tmr| {
                if (new._running_time_ms <= tmr._running_time_ms) {
                    //insert
                    new._next = tmr;
                    new._prev = tmr._prev;
                    if (tmr._prev) |prev| {
                        prev._next = new;
                    }

                    tmr._prev = new;
                    if (timer == self.list) {
                        self.list = new;
                    }
                    break;
                } else if (tmr._next == null) {
                    //insert at end
                    tmr._next = new;
                    new._prev = tmr;
                    break;
                } else {
                    timer = tmr._next;
                }
            }
        }
        new._init = true;
    }

    pub fn remove(self: *Self, detach: *Timer) Error!void {
        if (!detach._init) return Error.Uninitialized;

        Arch.criticalStart();
        defer Arch.criticalEnd();

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
    }
};
