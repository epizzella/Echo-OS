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

const OsCore = @import("os_core.zig");
const ArchInterface = @import("arch/arch_interface.zig");

var arch = ArchInterface.arch;
const os_config = &OsCore.getOsConfig;
const SyncContext = OsCore.SyncContext;
const Error = OsCore.Error;

pub const Task = struct {
    const Self = @This();

    _stack: []u32,
    _stack_ptr: usize,
    _state: State = State.ready,
    _queue: ?*TaskQueue = null,
    _subroutine: *const fn () anyerror!void,
    _subroutineErrHandler: ?*const fn (err: anyerror) void = null,
    _timeout: u32 = 0,
    _timed_out: bool = false,
    _priority: u5,
    _basePriority: u5,
    _to_tail: ?*Task = null,
    _to_head: ?*Task = null,
    _SyncContext: SyncContext = .{},
    _init: bool = false,
    _name: []const u8,

    pub const TaskConfig = struct {
        /// Task name
        name: []const u8,
        /// Task stack
        stack: []u32,
        /// Function executed by task
        subroutine: *const fn () anyerror!void,
        /// If `subroutine` returns an erorr that error will be passed to `subroutineErrHandler`.
        /// The task is suspsended after `subroutineErrHandler` completes, or if `subroutine` returns void.
        subroutineErrHandler: ?*const fn (err: anyerror) void = null,
        ///Priority level of the task.  Lower number = higher priority.
        priority: u5,
    };

    /// Create a task
    pub fn create_task(config: TaskConfig) Task {
        return Task{
            ._name = config.name,
            ._stack = config.stack,
            ._priority = config.priority,
            ._basePriority = config.priority,
            ._subroutine = config.subroutine,
            ._subroutineErrHandler = config.subroutineErrHandler,
            ._timeout = 0,
            ._stack_ptr = 0, //updated when os is started
        };
    }

    /// Add task to the OS
    pub fn init(self: *Self) void {
        if (!self._init) {
            task_control.addReady(self);
            self._init = true;
        }
    }

    /// Suspend the task
    pub fn suspendMe(self: *Self) Error!void {
        if (!self._init) return OsCore.Error.Uninitialized;
        task_control.addSuspended(self);
    }

    /// Resume the task
    pub fn resumeMe(self: *Self) Error!void {
        if (!self._init) return OsCore.Error.Uninitialized;
        task_control.addReady(self);
    }
};

pub const State = enum { running, ready, suspended, yeilded, blocked, blocked_timedout, exited };

pub var task_control: TaskControl = .{};

// 32 user accessable priority levels + idle task at lowest priority level
const MAX_PRIO_LEVEL = 33;
//idle task is the lowest priority.
pub const IDLE_PRIORITY_LEVEL: u32 = 32;
const PRIO_ADJUST: u5 = 31;
const ONE: u32 = 0x1;

pub const TaskControl = struct {
    table: [MAX_PRIO_LEVEL]TaskStateQ = [_]TaskStateQ{.{}} ** MAX_PRIO_LEVEL,
    ready_mask: u32 = 0, //          mask of ready tasks
    running_priority: u6 = 0x00, //  priority level of the current running task

    export var current_task: ?*volatile Task = null;
    export var next_task: *volatile Task = undefined;

    ///Initalize the stacks for every task added to the OS
    pub fn initAllStacks(self: *TaskControl) void {
        if (!OsCore.isOsStarted()) {
            for (&self.table) |*row| {
                var task = row.ready_tasks.head;
                while (true) {
                    if (task) |t| {
                        arch.initStack(t);
                        task = t._to_tail;
                    }
                    if (task == null) break;
                }
            }
        }
    }

    inline fn clearReadyBit(self: *TaskControl, priority: u6) void {
        self.ready_mask &= ~(ONE << (priorityAdjust[priority]));
    }

    inline fn setReadyBit(self: *TaskControl, priority: u6) void {
        self.ready_mask |= ONE << (priorityAdjust[priority]);
    }

    ///Set task ready to run
    pub fn readyTask(self: *TaskControl, task: *Task) void {
        if (task._queue) |q| _ = q.remove(task);
        self.addReady(task);
    }

    ///Set task as yeilded
    pub fn yeildTask(self: *TaskControl, task: *Task) void {
        if (task._queue) |q| _ = q.remove(task);
        if (self.table[task._priority].ready_tasks.head == null) {
            self.clearReadyBit(task._priority);
        }
        self.addYeilded(task);
    }

    ///Set task as suspended
    pub fn suspendTask(self: *TaskControl, task: *Task) void {
        if (task._queue) |q| _ = q.remove(task);
        if (self.table[task._priority].ready_tasks.head == null) {
            self.clearReadyBit(task._priority);
        }
        self.addSuspended(task);
    }

    ///Add task to the active task queue
    fn addReady(self: *TaskControl, task: *Task) void {
        self.table[task._priority].ready_tasks.insertAfter(task, null);
        self.setReadyBit(task._priority);
        task._state = State.ready;
        task._timeout = 0;
    }

    ///Add task to the yielded task queue
    fn addYeilded(self: *TaskControl, task: *Task) void {
        self.table[task._priority].yielded_tasks.insertAfter(task, null);
        task._state = State.yeilded;
    }

    ///Add task to the suspended task queue
    fn addSuspended(self: *TaskControl, task: *Task) void {
        self.table[task._priority].suspended_tasks.insertAfter(task, null);
        if (task._state != State.exited) task._state = State.suspended;
    }

    ///Pop the active task from its active queue
    pub fn popActive(self: *TaskControl) ?*Task {
        const head = self.table[self.running_priority].ready_tasks.pop();
        if (self.table[self.running_priority].ready_tasks.head == null) {
            self.clearReadyBit(self.running_priority);
        }

        return head;
    }

    ///Move the head task to the tail position of the active queue
    pub fn cycleActive(self: *TaskControl) void {
        if (self.running_priority < MAX_PRIO_LEVEL) {
            self.table[self.running_priority].ready_tasks.headToTail();
        }
    }

    ///Set `next_task` to the highest priority task that is ready to run
    pub fn setNextRunningTask(self: *TaskControl) void {
        self.running_priority = @clz(self.ready_mask);
        next_task = self.table[self.running_priority].ready_tasks.head.?;
        next_task._state = State.running;
    }

    ///Returns true if `current_task` and `next_task` are different
    pub fn validSwitch(self: *TaskControl) bool {
        _ = self;
        return current_task != next_task;
    }

    ///Updates the delayed time for each sleeping task
    pub fn updateTasksDelay(self: *TaskControl) void {
        for (&self.table) |*taskState| {
            if (taskState.yielded_tasks.head) |head| {
                var task = head;
                while (true) { //iterate over the priority level list
                    task._timeout -= 1;
                    if (task._timeout == 0) {
                        self.readyTask(task);
                    }

                    if (task._to_tail) |next| {
                        task = next;
                    } else {
                        break;
                    }
                }
            }
        }
    }

    pub fn addIdleTask(self: *TaskControl, idle_task: *Task) void {
        self.table[IDLE_PRIORITY_LEVEL].ready_tasks.insertAfter(idle_task, null);
    }

    const priorityAdjust: [32]u5 = .{ 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
};

const TaskStateQ = struct {
    ready_tasks: TaskQueue = .{},
    yielded_tasks: TaskQueue = .{},
    suspended_tasks: TaskQueue = .{},
    exited_tasks: TaskQueue = .{},
};

pub const TaskQueue = struct {
    head: ?*Task = null,
    tail: ?*Task = null,
    elements: u32 = 0,

    const Self = @This();

    ///Insert `insert_node` before `target_node`.  When `target_node` is null prepend to head
    pub fn insertBefore(self: *Self, insert_node: *Task, target_node: ?*Task) void {
        if (target_node) |t_node| {
            //insert before
            insert_node._to_head = t_node._to_head;
            insert_node._to_tail = t_node;
            t_node._to_head = insert_node;
            if (target_node == self.head) self.head = insert_node;
            if (insert_node._to_head) |insert_head| insert_head._to_tail = insert_node;
        } else {
            //prepend to head.
            if (self.head) |head| {
                insert_node._to_tail = head;
                head._to_head = insert_node;
                insert_node._to_head = null; //this should already be null.
            } else {
                self.tail = insert_node;
            }
            self.head = insert_node;
        }

        insert_node._queue = self;
        self.elements += 1;
    }

    ///Insert `insert_node` after `target_node`.  When `target_node` is null append to head
    pub fn insertAfter(self: *Self, insert_node: *Task, target_node: ?*Task) void {
        if (target_node) |t_node| {
            //insert after
            insert_node._to_tail = t_node._to_tail;
            insert_node._to_head = t_node;
            t_node._to_tail = insert_node;
            if (t_node == self.tail) self.tail = insert_node;
            if (insert_node._to_tail) |insert_tail| insert_tail._to_head = insert_node;
        } else {
            //append to tail.
            if (self.tail) |tail| {
                insert_node._to_head = tail;
                tail._to_tail = insert_node;
                insert_node._to_tail = null; //this should already be null.
            } else {
                self.head = insert_node;
            }
            self.tail = insert_node;
        }

        insert_node._queue = self;
        self.elements += 1;
    }

    //Insert a task into the queue based on its priority
    pub fn insertSorted(self: *Self, insert_node: *Task) void {
        var search: ?*Task = self.tail;
        while (true) {
            if (search) |s| {
                if (insert_node._priority >= s._priority) {
                    self.insertAfter(insert_node, s);
                    break;
                } else {
                    search = s._to_head;
                }
            } else {
                self.insertBefore(insert_node, search);
                break;
            }
        }
    }

    ///Pop the head node from the queue
    pub fn pop(self: *Self) ?*Task {
        const rtn = self.head orelse return null;
        self.head = rtn._to_tail;
        rtn._to_tail = null;
        self.elements -= 1;
        if (self.head) |new_head| {
            new_head._to_head = null;
        } else {
            self.tail = null;
        }
        rtn._queue = null;
        return rtn;
    }

    ///Returns true if the specified node is contained in the queue
    pub fn contains(self: *Self, node: *Task) bool {
        return node._queue == self;
    }

    ///Removes the specified task from the queue.  Returns false if the node is not contained in the queue.
    pub fn remove(self: *Self, node: *Task) bool {
        var rtn = false;

        if (self.contains(node)) {
            if (self.head == self.tail) { //list of 1
                self.head = null;
                self.tail = null;
            } else if (self.head == node) {
                if (node._to_tail) |towardTail| {
                    self.head = towardTail;
                    towardTail._to_head = null;
                }
            } else if (self.tail == node) {
                if (node._to_head) |towardHead| {
                    self.tail = towardHead;
                    towardHead._to_tail = null;
                }
            } else {
                if (node._to_head) |towardHead| {
                    towardHead._to_tail = node._to_tail;
                }
                if (node._to_tail) |towardTail| {
                    towardTail._to_head = node._to_head;
                }
            }

            node._to_head = null;
            node._to_tail = null;

            self.elements -= 1;
            node._queue = null;
            rtn = true;
        }

        return rtn;
    }

    ///Move the head task to the tail position
    pub fn headToTail(self: *Self) void {
        if (self.head != self.tail) {
            if (self.head != null and self.tail != null) {
                const temp = self.head;
                self.head.?._to_tail.?._to_head = null;
                self.head = self.head.?._to_tail;

                temp.?._to_tail = null;
                self.tail.?._to_tail = temp;
                temp.?._to_head = self.tail;
                self.tail = temp;
            }
        }
    }
};

pub fn taskTopRoutine() void {
    if (task_control.table[task_control.running_priority].ready_tasks.head) |running_task| {
        running_task._subroutine() catch |err| {
            if (running_task._subroutineErrHandler) |errHandler| {
                errHandler(err);
            }
        };
    }

    arch.criticalStart();
    if (task_control.popActive()) |active_task| {
        task_control.addSuspended(active_task);
        active_task._state = State.exited;
    }
    arch.criticalEnd();
    arch.runScheduler();
}
