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
const os_config = &OsCore.getOsConfig;
const Task = OsTask.Task;
const Error = OsCore.Error;

pub const Control = SyncControl.SyncControl;
const SyncContex = SyncControl.SyncContext;

pub const Semaphore = struct {
    const Self = @This();
    _name: []const u8,
    _count: usize,
    _syncContext: SyncContex,

    pub const CreateOptions = struct {
        /// Name of sempahore
        name: []const u8,
        /// Start value of the semaphore counter
        inital_value: usize,
    };

    /// Create a semaphore object
    pub fn create_semaphore(comptime options: CreateOptions) Self {
        return Self{
            ._name = options.name,
            ._count = options.inital_value,
            ._syncContext = .{},
        };
    }

    /// Add the semaphore to the OS
    pub fn init(self: *Self) Error!void {
        try Control.add(&self._syncContext);
    }

    /// Remove the semaphore from the OS
    pub fn deinit(self: *Self) Error!void {
        try Control.remove(&self._syncContext);
    }

    pub const WaitOptions = struct {
        /// an optional timeout in milliseconds.  When set to a non-zero value the
        /// task will block for the amount of time specified. If the timeout expires
        /// before the count is non-zero acquire() will return OsError.TimedOut. When
        /// set to zero the task will block until the count is non-zero.
        timeout_ms: u32 = 0,
    };

    /// Decrements the counter.  If the counter is at zero the running task will be
    /// blocked until the counter's value becomes non zero. Cannot be called from an
    /// interrupt.
    pub fn wait(self: *Self, options: WaitOptions) Error!void {
        _ = try SyncControl.validateCallMajor();
        if (!self._syncContext._init) return Error.Uninitialized;
        Arch.criticalStart();
        defer Arch.criticalEnd();

        if (self._count == 0) {
            //locked
            try Control.blockTask(&self._syncContext, options.timeout_ms);
        } else {
            //unlocked
            self._count -= 1;
        }
    }

    pub const PostOptions = struct {
        runScheduler: bool = true,
    };

    /// Increments the counter.  If the pending task is higher priority
    /// than the running task the scheduler is called.
    pub fn post(self: *Self, options: PostOptions) Error!void {
        Arch.criticalStart();
        defer Arch.criticalEnd();
        const running_task = try SyncControl.validateCallMinor();

        if (self._syncContext._pending.head) |head| {
            task_control.readyTask(head);
            if (head._priority < running_task._priority and options.runScheduler) {
                Arch.criticalEnd();
                Arch.runScheduler();
            }
        } else {
            self._count += 1;
        }
    }

    /// Readys the task if it is waiting on the semaphore.  When the task next
    /// runs acquire() will return OsError.Aborted
    pub fn abortAcquire(self: *Self, task: *Task) Error!void {
        try Control.abort(&self._syncContext, task);
    }
};
