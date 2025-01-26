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
const Task = OsTask.Task;
const SyncControl = @import("sync_control.zig");
const ArchInterface = @import("../arch/arch_interface.zig");

const Arch = ArchInterface.Arch;
const Error = OsCore.Error;
const task_control = &OsTask.task_control;
pub const Control = SyncControl.SyncControl;
const SyncContex = SyncControl.SyncContext;

pub const EventGroup = struct {
    const Self = @This();
    const EventContext = OsCore.SyncContext;

    _name: []const u8,
    _event: usize,
    _syncContex: SyncContex,

    pub const EventTrigger = OsCore.SyncContext.EventTrigger;

    const EventGroupConfig = struct {
        //Name of the event group
        name: []const u8,
    };

    /// Create an event group object
    pub fn createEventGroup(config: EventGroupConfig) Self {
        return Self{
            ._name = config.name,
            ._event = 0,
            ._syncContex = .{},
        };
    }

    /// Add the event group to the OS
    pub fn init(self: *Self) Error!void {
        if (!self._syncContex._init) {
            try Control.add(&self._syncContex);
        }
    }

    pub fn deinit(self: *Self) Error!void {
        try Control.remove(&self._syncContext);
    }

    const writeOptions = struct {
        /// The event flag
        event: usize,
    };

    /// Set the event flag of an event group
    pub fn writeEvent(self: *Self, options: writeOptions) Error!void {
        const running_task = try SyncControl.validateCallMinor();
        if (!self._syncContex._init) return Error.Uninitialized;

        Arch.criticalStart();
        defer Arch.criticalEnd();
        self._event = options.event;
        var pending_task = self._syncContex._pending.head;
        var highest_pending_prio: usize = OsTask.IDLE_PRIORITY_LEVEL;
        while (true) {
            if (pending_task) |task| {
                const event_triggered = checkEventTriggered(task._SyncContext, self._event);
                if (event_triggered) {
                    task_control.readyTask(task);
                    task._SyncContext.triggering_event = self._event;
                    if (task._priority < highest_pending_prio) {
                        highest_pending_prio = task._priority;
                    }
                }
                pending_task = task._to_tail;
            } else {
                break;
            }
        }

        if (highest_pending_prio < running_task._priority) {
            Arch.criticalEnd();
            Arch.runScheduler();
        }
    }

    /// Read the event flag from the event group
    pub fn readEvent(self: *Self) Error!usize {
        if (!self._syncContex._init) return Error.Uninitialized;
        return self._event;
    }

    pub const AwaitEventOptions = struct {
        /// The event bits to pend on
        event_mask: usize,
        /// The state change of the event bits to pend on
        PendOn: EventTrigger,
        /// The timeout in milliseconds.  Set to 0 to pend indefinitely.
        timeout_ms: u32 = 0,
    };

    /// Block the running task until the pending event is set.  If the pending event
    /// is set when awaitEvent is called the running task will not be blocked.
    pub fn awaitEvent(self: *Self, options: AwaitEventOptions) Error!usize {
        const running_task = try SyncControl.validateCallMajor();
        if (!self._syncContex._init) return Error.Uninitialized;

        running_task._SyncContext.pending_event = options.event_mask;
        running_task._SyncContext.trigger_type = options.PendOn;

        Arch.criticalStart();
        defer Arch.criticalEnd();

        const event_triggered = checkEventTriggered(running_task._SyncContext, self._event);
        if (event_triggered) {
            running_task._SyncContext.triggering_event = self._event;
        } else {
            try Control.blockTask(&self._syncContex, options.timeout_ms);
        }

        return running_task._SyncContext.triggering_event;
    }

    fn checkEventTriggered(eventContext: EventContext, current_event: usize) bool {
        return switch (eventContext.trigger_type) {
            EventTrigger.all_set => (current_event & eventContext.pending_event) == current_event,
            EventTrigger.all_clear => (~current_event & eventContext.pending_event) == current_event,
            EventTrigger.any_set => current_event & eventContext.pending_event > 0,
            EventTrigger.any_clear => ~current_event & eventContext.pending_event > 0,
        };
    }

    pub const AbortOptions = struct {
        /// The task to abort pend and ready
        task: *Task,
    };

    /// Readys the task if it is waiting on the event group.  When the task next
    /// runs awaitEvent() will return OsError.Aborted
    pub fn abortAwait(self: *Self, options: AbortOptions) Error!void {
        try Control.abort(&self._syncContext, options.task);
    }
};
