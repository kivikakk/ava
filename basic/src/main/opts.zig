const args = @import("args");

pub const Global = struct {
    help: bool = false,

    pub const shorthands = .{ .h = "help" };
};

pub const Command = union(enum) {
    repl: Repl,
    run: Run,
    compile: Compile,
    pp: Pp,
    ast: Ast,
    bc: Bc,
};

pub const Repl = struct {
    pp: bool = false,
    ast: bool = false,
    bc: bool = false,
};

pub const Run = struct {
    bas: bool = false,
    avc: bool = false,
};

pub const Compile = void;
pub const Pp = void;
pub const Ast = void;

pub const Bc = struct {
    bas: bool = false,
    avc: bool = false,
};

pub var global: args.ParseArgsResult(Global, Command) = undefined;
