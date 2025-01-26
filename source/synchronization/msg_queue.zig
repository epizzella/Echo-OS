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
const ArchInterface = @import("../arch/arch_interface.zig");

const Task = OsTask.Task;
const task_control = &OsTask.task_control;
const Arch = ArchInterface.Arch;

pub const Control = SyncControl.SyncControl;
const SyncContex = SyncControl.SyncContext;
const QError = error{ QueueFull, QueueEmpty, QueueUninitialized };
const OsError = OsCore.Error;
const Error = QError || OsError;

/// Options for creating a type of message queue
pub const CreateOptions = struct {
    /// The type that the message queue will accept
    MsgType: type,
    /// The maximum number of messages that this type of queue can contain
    buffer_size: usize,
};

/// Create a message queue for a specific type
pub fn createMsgQueueType(comptime opt: CreateOptions) type {
    return struct {
        const Self = @This();

        _name: []const u8,
        _buffer: [opt.buffer_size]opt.MsgType,
        _head: usize,
        _tail: usize,
        _empty: bool = true,
        _syncContex: SyncContex = SyncContex{},

        pub const InitOptions = struct {
            /// Messages queue name
            name: []const u8,
            /// Inital value for all buffer elements
            inital_val: opt.MsgType,
        };

        /// Create a message queue
        pub fn createQueue(optQ: InitOptions) Self {
            return Self{
                ._name = optQ.name,
                ._buffer = [_]opt.MsgType{optQ.inital_val} ** opt.buffer_size,
                ._head = 0,
                ._tail = 0,
            };
        }

        /// Add message queue to OS
        pub fn init(self: *Self) Error!void {
            if (!self._syncContex._init) {
                try Control.add(&self._syncContex);
            }
        }

        pub fn deinit(self: *Self) Error!void {
            try Control.remove(&self._syncContext);
        }

        pub fn pushMsg(self: *Self, msg: opt.MsgType) Error!void {
            _ = try SyncControl.validateCallMinor();
            Arch.criticalStart();
            defer Arch.criticalEnd();

            if (self._isfull()) return Error.QueueFull;

            //do a mem copy instead of using = ?
            self._buffer[self._head] = msg;
            if (self._head != opt.buffer_size - 1) {
                self._head += 1;
            } else {
                self._head = 0;
            }

            self._empty = false;

            if (self._syncContex._pending.head) |head| {
                task_control.readyTask(head);
                if (head._priority < task_control.running_priority) {
                    Arch.criticalEnd();
                    Arch.runScheduler();
                }
            }
        }

        fn popMsg(self: *Self) Error!opt.MsgType {
            if (self._empty) return Error.QueueEmpty;

            //do a mem copy instead of using = ?
            const msg = self._buffer[self._tail];
            if (self._tail != opt.buffer_size - 1) {
                self._tail += 1;
            } else {
                self._tail = 0;
            }

            if (self._head == self._tail) self._empty = true;

            return msg;
        }

        const AwaitOptions = struct {
            timeout_ms: u32 = 0,
        };

        pub fn awaitMsg(self: *Self, options: AwaitOptions) Error!opt.MsgType {
            _ = try SyncControl.validateCallMajor();
            Arch.criticalStart();
            defer Arch.criticalEnd();

            if (self._empty) {
                try Control.blockTask(&self._syncContex, options.timeout_ms);
                Arch.criticalStart();
            }

            return self.popMsg();
        }

        pub fn abortAwaitMsg(self: *Self, task: Task) Error!void {
            try Control.abort(&self._syncContext, task);
        }

        pub fn flush(self: *Self) void {
            Arch.criticalStart();
            defer Arch.criticalEnd();

            self._head = 0;
            self._tail = 0;
            self._empty = true;
        }

        pub fn isEmpty(self: *Self) bool {
            Arch.criticalStart();
            defer Arch.criticalEnd();

            return self._empty;
        }

        inline fn _isfull(self: *Self) bool {
            return !self._empty and (self._head == self._tail);
        }

        pub fn isFull(self: *Self) bool {
            Arch.criticalStart();
            defer Arch.criticalEnd();

            return self._isfull();
        }
    };
}
