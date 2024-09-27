const std = @import("std");
const protocol = @import("../lib.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

const CompactSizeUint = @import("bitcoin-primitives").types.CompatSizeUint;

/// SendCmpctMessage represents the "sendcmpct" message
///
/// https://developer.bitcoin.org/reference/p2p_networking.html#sendcmpct
pub const SendCmpctMessage = struct {
    announce: bool,
    version: u64,

    pub const Error = error{
        InvalidAnnounceValue,
    };

    pub fn name() *const [12]u8 {
        return protocol.CommandNames.SENDCMPCT ++ [_]u8{0} ** 3;
    }

    /// Returns the message checksum
    ///
    /// Computed as `Sha256(Sha256(self.serialize()))[0..4]`
    pub fn checksum(self: *const SendCmpctMessage) [4]u8 {
        var digest: [32]u8 = undefined;
        var hasher = Sha256.init(.{});
        const writer = hasher.writer();
        self.serializeToWriter(writer) catch unreachable; // Sha256.write is infallible
        hasher.final(&digest);

        Sha256.hash(&digest, &digest, .{});

        return digest[0..4].*;
    }
    /// Serialize the message as bytes and write them to the Writer.
    pub fn serializeToWriter(self: *const SendCmpctMessage, w: anytype) !void {
        comptime {
            if (!std.meta.hasFn(@TypeOf(w), "writeInt")) @compileError("Expects writer to have 'writeInt'.");
        }
        // Write announce (1 byte)
        try w.writeInt(u8, if (self.announce) 0x01 else 0x00, .little);
        // Write version (8 bytes, little-endian)
        try w.writeInt(u64, self.version, .little);
    }

    /// Serialize a message as bytes and return them.
    pub fn serialize(self: *const SendCmpctMessage, allocator: std.mem.Allocator) ![]u8 {
        const serialized_len = self.hintSerializedLen();

        const buffer = try allocator.alloc(u8, serialized_len);
        errdefer allocator.free(buffer);

        var fbs = std.io.fixedBufferStream(buffer);
        try self.serializeToWriter(fbs.writer());

        return buffer;
    }
    pub fn deserializeReader(allocator: std.mem.Allocator, r: anytype) !SendCmpctMessage {
        _ = allocator;
        comptime {
            if (!std.meta.hasFn(@TypeOf(r), "readInt")) @compileError("Expects reader to have 'readInt'.");
        }

        var msg: SendCmpctMessage = undefined;

        // Read announce (1 byte)
        const announce_byte = try r.readByte();

        // Validate announce (must be 0x00 or 0x01)
        if (announce_byte != 0x00 and announce_byte != 0x01) {
            return SendCmpctMessage.Error.InvalidAnnounceValue;
        }

        msg.announce = announce_byte == 0x01;

        // Read version (8 bytes, little-endian)
        msg.version = try r.readInt(u64, .little);

        return msg;
    }

    pub fn hintSerializedLen(self: *const SendCmpctMessage) usize {
        _ = self;
        return 1 + 8;
    }
    // Equality check
    pub fn eql(self: *const SendCmpctMessage, other: *const SendCmpctMessage) bool {
        return self.announce == other.announce and self.version == other.version;
    }
};
// TESTS

test "ok_full_flow_SendCmpctMessage" {
    const allocator = std.testing.allocator;

    const msg = SendCmpctMessage{
        .announce = true,
        .version = 1,
    };

    // Serialize the message
    const payload = try msg.serialize(allocator);
    defer allocator.free(payload);

    // Deserialize the message
    var fbs = std.io.fixedBufferStream(payload);
    const reader = fbs.reader();
    const deserialized_msg = try SendCmpctMessage.deserializeReader(allocator, reader);

    try std.testing.expect(msg.eql(&deserialized_msg));
}
