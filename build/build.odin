package build_mani

import "core:fmt"
import "../odin-build/build"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:c/libc"

Conf_Type :: enum {
    Debug,
    Release,
    Fast,
    Test,
}

Target :: struct {
    name: string,
    platform: build.Platform,
    conf: Conf_Type,
}
Project :: build.Project(Target)

CURRENT_PLATFORM :: build.Platform{ODIN_OS, ODIN_ARCH}


copy_dll :: proc(config: build.Config) -> int {
    out_dir := filepath.dir(config.out, context.temp_allocator)

    cmd := fmt.tprintf("xcopy /y /i \"odin-lua\\bin\\windows\\lua542.dll\" \"%s\\lua542.dll\"", ODIN_ROOT, out_dir)
    return build.syscall(cmd, true)
}

copy_assets :: proc(config: build.Config) -> int {
   
    return 0
}

add_targets :: proc(project: ^Project) {
    build.add_target(project, Target{"deb", CURRENT_PLATFORM, .Debug})
    build.add_target(project, Target{"rel", CURRENT_PLATFORM, .Release})
    build.add_target(project, Target{"fast", CURRENT_PLATFORM, .Fast})
    build.add_target(project, Target{"test", CURRENT_PLATFORM, .Test})
}


configure_target :: proc(project: Project, target: Target) -> (config: build.Config) {
    config = build.config_make()
 
    config.platform = target.platform
    config.name = target.name
    exe_ext, exe_name := "", ""

    if target.platform.os == .Windows {
        exe_ext = ".exe"
    }
    if target.conf == .Test {
        exe_name = "test"
        config.src = "./test"
    } else {
        exe_name = "manigen"
        config.src = "./manigen2"
    }
    
    switch target.conf {
        case .Debug: {
            config.flags += {.Debug}
            config.optimization = .None
        }

        case .Release: {
            config.optimization = .Speed
        }

        case .Fast: {
            config.optimization = .Speed
            config.flags += {.Disable_Assert, .No_Bounds_Check}
        }

        case .Test: {
            if target.platform.os == .Windows {
                build.add_post_build_command(&config, "copy-dll", copy_dll)
            } 
            config.optimization = .None
            config.flags += {.Debug, .Ignore_Unknown_Attributes}
           
        }
    }
        
    config.out = fmt.aprintf("out/%s/%s%s", target.name, exe_name, exe_ext)
    return
}


main :: proc() {
    project: build.Project(Target)
    project.configure_target_proc = configure_target
    options := build.build_options_make_from_args(os.args[1:])
    add_targets(&project)
    build.build_project(project, options)
}