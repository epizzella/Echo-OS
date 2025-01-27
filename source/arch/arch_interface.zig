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

const Task = @import("../task.zig").Task;
const builtin = @import("builtin");
const std = @import("std");
const cpu = std.Target.arm.cpu;

const TestArch = @import("test/test_arch.zig");
const ArmCortexM = @import("arm-cortex-m/arch.zig");
//Import future architecture implementions here

pub const Arch = getArch: {
    const cpu_model = builtin.cpu.model.*;

    if (builtin.is_test == true) {
        break :getArch TestArch;
    } else if (std.meta.eql(cpu_model, cpu.cortex_m0) or //
        std.meta.eql(cpu_model, cpu.cortex_m0plus) or //
        std.meta.eql(cpu_model, cpu.cortex_m3) or //
        std.meta.eql(cpu_model, cpu.cortex_m4) or //
        std.meta.eql(cpu_model, cpu.cortex_m7))
    {
        break :getArch ArmCortexM;
    } else {
        @compileError("Unsupported architecture selected.");
    }
};
