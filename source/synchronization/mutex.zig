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
const TaskQueue = OsTask.TaskQueue;
const SyncControl = @import("sync_control.zig");
const ArchInterface = @import("../arch/arch_interface.zig");

const Arch = ArchInterface.Arch;

const task_control = &OsTask.task_control;
const Task = OsTask.Task;
const os_config = &OsCore.getOsConfig;
const Error = OsCore.Error;
pub const Control = SyncControl.SyncControl;
const SyncContex = SyncControl.SyncContext;

pub const Mutex = struct {
    const Self = @This();
    const CreateOptions = struct { name: []const u8, enable_priority_inheritance: bool = false };

    _name: []const u8,
    _owner: ?*Task = null,
    _prioInherit: bool,
    _syncContext: SyncContex = .{},

    /// Create a mutex object
    pub fn create_mutex(options: CreateOptions) Self {
        return Self{
            ._name = options.name,
            ._prioInherit = options.enable_priority_inheritance,
        };
    }

    /// Add the mutex to the OS
    pub fn init(self: *Self) Error!void {
        if (!self._syncContext._init) {
            try Control.add(&self._syncContext);
        }
    }

    /// Remove the mutex from the OS
    pub fn deinit(self: *Self) Error!void {
        try Control.remove(&self._syncContext);
    }

    pub const AquireOptions = struct {
        /// An optional timeout in milliseconds.  When set to a non-zero value the task
        /// will block for the amount of time specified. If the timeout expires before
        /// the mutex is unlocked acquire() will return OsError.TimedOut. When set to
        /// zero the task will block until the mutex unlocks.
        timeout_ms: u32 = 0,
    };

    /// Locks the mutex and gives the calling task ownership. If the mutex
    /// is lock when acquire() is called the running task will be blocked until
    /// the mutex is unlocked. Cannot be called from an interrupt.
    pub fn acquire(self: *Self, options: AquireOptions) Error!void {
        const running_task = try SyncControl.validateCallMajor();
        if (running_task == self._owner) return Error.MutexOwnerAquire;
        Arch.criticalStart();
        defer Arch.criticalEnd();

        if (self._owner) |owner| {
            //locked

            //Priority Inheritance
            if (self._prioInherit and running_task._priority > owner._priority) {
                owner._priority = running_task._priority;
                task_control.readyTask(owner);
            }

            try Control.blockTask(&self._syncContext, options.timeout_ms);
        } else {
            //unlocked
            self._owner = running_task;
        }
    }

    /// Unlocks the mutex and removes ownership from the running task. If the
    /// running task is not the owner OsError.TaskNotOwner is returned. Cannot be
    /// called from an interrupt.
    pub fn release(self: *Self) Error!void {
        Arch.criticalStart();
        defer Arch.criticalEnd();
        const active_task = try SyncControl.validateCallMajor();

        if (active_task == self._owner) {
            self._owner = self._syncContext._pending.head;

            //Priority Inheritance
            if (self._prioInherit and active_task._priority != active_task._basePriority) {
                if (task_control.popRunningTask()) |r_task| {
                    r_task._priority = r_task._basePriority;
                    task_control.readyTask(r_task);
                    Arch.criticalEnd();
                    Arch.runScheduler();
                }
            } else if (self._owner) |head| {
                task_control.readyTask(head);
                if (head._priority < task_control.running_priority) {
                    Arch.criticalEnd();
                    Arch.runScheduler();
                }
            }
        } else {
            return Error.InvalidMutexOwner;
        }
    }

    /// Readys the task if it is waiting on the mutex. When the task next
    /// runs acquire() will return OsError.Aborted.
    /// * task - The task to abort & ready
    pub fn abortAcquire(self: *Self, task: *Task) Error!void {
        try Control.abort(&self._syncContext, task);
    }
};
