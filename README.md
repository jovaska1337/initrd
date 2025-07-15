## Simple initial ramdisk generator

This is a simple shell script based initrd system. You should make edits to `default.env` and
create a configuration file (see `rescue.conf` and `live.conf`) which adds the required tasks
and files to the initrd in order to mount the root filesystem.

Configuration files can define environment variables into the environment block and define
configuration directives which add files, tasks, etc. into the initrd image. All directives
are defined in `lib/config.sh`. At least one boot task must be added.

Generate the initrd by issuing `./generate.sh <config> <output>`
