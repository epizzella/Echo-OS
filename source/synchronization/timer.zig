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
const Semaphore = OsSemaphore.Semaphore;

const Task = OsTask.Task;
const TimerContext = SyncControl.TimerContext;
pub const Control = SyncControl.TimerControl;

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

        try Control.start(self);
    }

    pub fn cancel(self: *Self) Error!void {
        if (self._state != State.running) return Error.TimerNotRunning;
        try Control.stop(self);
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

        var timer = Control.getExpiredList() orelse continue;
        timer._callback();
        if (timer._autoreload) {
            timer._running_time_ms = timer._timeout_ms;
            try Control.restart(timer);
        } else {
            try Control.stop(timer);
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
