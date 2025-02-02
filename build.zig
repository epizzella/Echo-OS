const std = @import("std");
const cpu = std.Target.arm.cpu;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_software_timers = b.option(bool, "enable_software_timers", "Software Timer: Enable = True; Disable = False") orelse false;

    //future configurable features:
    //  Debug info
    //  Statistics Task

    const os_features = b.addOptions();
    os_features.addOption(bool, "enable_software_timers", enable_software_timers);

    const echo = b.addModule("EchoOS", .{
        .root_source_file = b.path("os.zig"),
        .target = target,
        .optimize = optimize,
    });

    echo.addOptions("echoConfig", os_features);

    const cpu_model = target.result.cpu.model.*;

    if (std.meta.eql(cpu_model, cpu.cortex_m0) or //
        std.meta.eql(cpu_model, cpu.cortex_m0plus))
    {
        std.log.info("Echo OS target: armv6m", .{});
        echo.addAssemblyFile(b.path("source/arch/arm-cortex-m/armv6m.s"));
    } else if (std.meta.eql(cpu_model, cpu.cortex_m3) or //
        std.meta.eql(cpu_model, cpu.cortex_m4) or //
        std.meta.eql(cpu_model, cpu.cortex_m7))
    {
        std.log.info("Echo OS target: armv7m", .{});
        if (target.query.abi) |abi| {
            if (abi == std.Target.Abi.eabihf) {
                echo.addAssemblyFile(b.path("source/arch/arm-cortex-m/armv7m_hf.s"));
            } else if (abi == std.Target.Abi.eabi) {
                echo.addAssemblyFile(b.path("source/arch/arm-cortex-m/armv7m.s"));
            } else {
                std.log.err("Invalid Abi. Abi should equal 'eabi' or 'eabihf'", .{});
            }
        } else {
            std.log.err("Abi not set. Abi should equal 'eabi' or 'eabihf'", .{});
        }
    } else {
        std.log.err("Unsupported architecture selected.", .{});
    }
}
