# Echo OS

Echo OS is a Real Time Operating System written in Zig.  As is tradition in the realm of RTOSes, Echo OS is really more of a real time kernel than an actual OS.

## Features

Echo OS has the following features:

- Premptive priority based scheduler
  - 32 priority levels for user tasks plus 1 resevered priority level (lowest prioirty) for the idle task
  - Unlimited tasks per priority level
- Task Syncronization
  - Event Groups
  - Mutexes
  - Semaphores
- Message Queues
- Software Timers
- Tasks return anyerror!void.  Users have the option to provide an error handler callback.

## Supported Architectures

- [X] ARMv6-M
- [X] ARMv7-M
- [ ] ARMv8-M
- [ ] ARMv8.1-M
- [ ] RISC-V

## Getting Started

To add the master branch of Echo Os to your project:

```
zig fetch --save git+https://github.com/epizzella/Echo-OS
```

To add a tagged version of Echo Os to your project:

```
# Replace <REPLACE ME> with the version of Echo OS that you want to use
zig fetch --save git+https://github.com/epizzella/Echo-OS#<REPLACE ME>

```

Then add the following to your ```build.zig```:

```
const rtos = b.dependency("EchoOS", .{ .target = target, .optimize = optimize });
elf.root_module.addImport("EchoOS", rtos.module("EchoOS"));
```

Echo OS uses the ```cpu_model``` field in the ```target``` argument at comptime to pull in the architecture specific files.  Example:

```
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .abi = .eabi,
        .os_tag = .freestanding,
    });
```

## API

The entire API is accessabile through a single file:  os.zig.  You can use os.zig via @import: ```const Os = @import("EchoOS");```

### Basic Example

The following is a basic example of creating a task and starting multitasking.  A single task is created and multitasking is started.

```
const Os = @import("EchoOS");   //Import Echo OS 
const Task = Os.Task

//task 1 subroutine
fn task1() !void {  
  while(true) {}
}

//task stack
const stackSize = 25;
var stack1: [stackSize]u32 = [_]u32{0xDEADC0DE} ** stackSize;   

//Create a task
var tcb = Task.create_task(.{
    .name = "task",
    .priority = 1,
    .stack = &stack1,
    .subroutine = &task1,
});

export fn main() void() {
  //Initialize drivers before starting

  // initalize the task & make the OS aware of it
  tcb.init();  

  //Start multitasking
  Os.startOS(  
    .clock_config = .{
        .cpu_clock_freq_hz = 64_000_000,
        .os_sys_clock_freq_hz = 1_000,
    },
  )
  
  unreachable;
}
```

For a more detailed example please refer to the [Echo OS example projects.](https://github.com/epizzella/Echo-OS-Examples)
