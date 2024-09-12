pub const UART: *volatile u8 = @ptrFromInt(0xf000_0000);
pub const UART_STATUS: *volatile u16 = @ptrFromInt(0xf000_0000);
pub const CSR_EXIT: *volatile u8 = @ptrFromInt(0xf001_0000);
