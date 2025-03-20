# Echo OS

Echo OS is a Real Time Operating System written in Zig. As is tradition in the realm of RTOSes, Echo OS is really more of a real time kernel than an actual OS.

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
- Tasks return anyerror!void. Users have the option to provide an error handler callback.

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
zig fetch --save git+https://github.com/epizzella/Echo-OS#<REPLACE ME>
Replace <REPLACE ME> with the version of Echo OS that you want to use I.E
zig fetch --save git+https://github.com/epizzella/Echo-OS#0.1.0
```

Then define the target. Echo OS uses the ```cpu_model``` to pull in the architecture specific files. Example:

```
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = std.Target.Query.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .abi = .eabi,
        .os_tag = .freestanding,
    });

```
Next add Echo Os as a dependacy. The target and optimization level are required. There are also several options that can be set or ommited. Omitted options are set to their default value.

| Option Name                   | Type   | Default Value | Description |
| :---------------------------- | :----: | :-----------: | :-----------| 
| enable_software_timers        | bool   |    false      | Enables software timers. |
| software_timers_task_priority | u5     |     31        | <p>The priority of the software timer task.<br>DNC when enable_software_timers is false.</p> |
| software_timers_stack_size    | u32    |      0        | The size of the software timer stack.&#10;Total size in bytes = software_timers_stack_size * @sizeof(usize).&#10;DNC when enable_software_timers is false. |

Example of adding Echo Os as a dependacy in ```build.zig```:

```
    const timer_pro: u5 = 5;
    const timer_stack_size: u32 = 50;

    //Add RTOS package
    const rtos = b.dependency("EchoOS", .{
        .target = target,
        .optimize = optimize,
        // Echo OS options
        .enable_software_timers = true,
        .software_timers_task_priority = timer_pro,
        .software_timers_stack_size = timer_stack_size,
    });

elf.root_module.addImport("EchoOS", rtos.module("EchoOS"));
```

## API

The entire API is accessabile through a single file: os.zig. You can use os.zig via @import: ```const Os = @import("EchoOS");```

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
