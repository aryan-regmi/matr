const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const mutt = @import("mutt");

// TODO: Turn errors into panics?

/// Checks if a type is a number.
fn isNumber(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => return true,
        else => return false,
    }
}

/// Represents a matrix of type `T`.
///
/// # Note
/// It is recommend to use an arena as the allocator in order to make freeing temporary matricies simple.
pub fn Matrix(comptime T: type) type {
    return struct {
        pub const Error = error{
            InvalidSize,
            InvalidSlice,
            RowIdxOutOfBounds,
            ColIdxOutOfBounds,
            InvalidRowSize,
            InvalidColSize,
            ResizeFailed,
            InvalidDimensions,
            InvalidMulDimensions,
            InitFailed,
        };

        /// Converts a `Matrix.Error` to `[]const u8`.
        pub fn errToStr(err: Error) []const u8 {
            switch (err) {
                Error.InvalidSize => return "Invalid size: The matrix must have at least one row and column",
                Error.InvalidSlice => return "Invalid slice: The slice must have `nrows * ncols` elements to create a valid matrix",
                Error.RowIdxOutOfBounds => return "Index out of bounds: The row index must be less than the number of rows in the matrix",
                Error.ColIdxOutOfBounds => return "Index out of bounds: The column index must be less than the number of columns in the matrix",
                Error.InvalidRowSize => return "Invalid row: The row must have as many elements as the number of columns in the matrix",
                Error.InvalidColSize => return "Invalid column: The column must have as many elements as the number of rows in the matrix",
                Error.ResizeFailed => return "Resize failed: The matrix could not be resized successfully",
                Error.InvalidDimensions => return "Invalid dimensions: The two matricies must have the same number of rows and columns",
                Error.InvalidMulDimensions => return "Invalid dimensions: The number of rows in the `other` matrix must equal the number of columns in `self`",
                Error.InitFailed => return "Failed to allocate space for the matrix",
            }
        }

        const Self = @This();

        /// Allocator used for internal memory management.
        allocator: Allocator,

        /// The elements of the matrix.
        elems: []T = undefined,

        /// Number of rows.
        nrows: usize = 0,

        /// Number of columns.
        ncols: usize = 0,

        /// Number of elements reserved.
        capacity: usize = 0,

        /// Gets the array index given a matrix index.
        fn arrayIdx(self: *const Self, row: usize, col: usize) usize {
            return self.ncols * row + col;
        }

        /// Creates a new, empty matrix.
        ///
        /// # Note
        /// Nothing is allocated until the first push.
        pub fn init(allocator: Allocator) Self {
            return Self{ .allocator = allocator };
        }

        /// Creates a new, empty matrix with memory reserved for `nrows * ncols` elements.
        pub fn initCapacity(allocator: Allocator, nrows: usize, ncols: usize) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init(allocator);
            }

            const elems = try allocator.alloc(T, nrows * ncols);
            return Self{ .allocator = allocator, .elems = elems, .capacity = nrows * ncols };
        }

        /// Creates a new matrix from the given slice.
        ///
        /// # Note
        /// The slice must have `nrows * ncols` elements, and the number of rows and columns must be at least 1.
        pub fn initFromSlice(allocator: Allocator, slice: []const T, nrows: usize, ncols: usize) !Self {
            // Input validation
            {
                if ((nrows == 0) or (ncols == 0)) {
                    return Error.InvalidSize;
                }
                if (slice.len != nrows * ncols) {
                    return Error.InvalidSlice;
                }
            }

            var out = try Self.initCapacity(allocator, nrows, ncols);
            out.nrows = nrows;
            out.ncols = ncols;

            // Call `clone` of `T` if it's cloneable, otherwise just copy
            const is_cloneable = comptime mutt.clone.isClone(T).valid;
            if (is_cloneable) {
                for (0..nrows) |i| {
                    for (0..ncols) |j| {
                        out.elems[out.arrayIdx(i, j)] = slice[out.arrayIdx(i, j)].clone();
                    }
                }
            } else {
                for (0..nrows) |i| {
                    for (0..ncols) |j| {
                        out.elems[out.arrayIdx(i, j)] = slice[out.arrayIdx(i, j)];
                    }
                }
            }

            return out;
        }

        /// Creates a new matrix of the specified size, with all elements set to `value`.
        pub fn initWithValue(allocator: Allocator, nrows: usize, ncols: usize, value: T) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init(allocator);
            }

            var out = try Self.initCapacity(allocator, nrows, ncols);
            out.nrows = nrows;
            out.ncols = ncols;

            const is_cloneable = comptime mutt.clone.isClone(T).valid;
            if (is_cloneable) {
                for (0..nrows * ncols) |i| {
                    out.elems[i] = value.clone();
                }
            } else {
                for (0..nrows * ncols) |i| {
                    out.elems[i] = value;
                }
            }

            return out;
        }

        /// Creates an identity matrix of the specified size.
        pub fn identity(allocator: Allocator, size: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create an `identity` matrix");
            };

            var out = try Self.initWithValue(allocator, size, size, 0);
            for (0..size) |i| {
                for (0..size) |j| {
                    if (i == j) {
                        out.elems[out.arrayIdx(i, j)] = 1;
                    }
                }
            }

            return out;
        }

        /// Creates a matrix of the specified size, filled with 0.
        pub fn zeros(allocator: Allocator, nrows: usize, ncols: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create an `zeros` matrix");
            };

            return Self.initWithValue(allocator, nrows, ncols, 0);
        }

        /// Creates a matrix of the specified size, filled with 1.
        pub fn ones(allocator: Allocator, nrows: usize, ncols: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create an `zeros` matrix");
            };

            return Self.initWithValue(allocator, nrows, ncols, 1);
        }

        /// Frees the memory used by the matrix.
        pub fn deinit(self: *const Self) void {
            if (self.capacity > 0) {
                self.allocator.free(self.elems);
            }
        }

        /// Returns the vaule at the specified index of the matrix.
        pub fn get(self: *const Self, row: usize, col: usize) !T {
            // Input validation
            {
                if (row > self.nrows) {
                    return Error.RowIdxOutOfBounds;
                }
                if (col >= self.ncols) {
                    return Error.ColIdxOutOfBounds;
                }
            }

            return self.elems[self.arrayIdx(row, col)];
        }

        /// Returns a pointer to the specified index of the matrix.
        pub fn getPtr(self: *Self, row: usize, col: usize) !*T {
            // Input validation
            {
                if (row > self.nrows) {
                    return Error.RowIdxOutOfBounds;
                }
                if (col >= self.ncols) {
                    return Error.ColIdxOutOfBounds;
                }
            }

            return @ptrCast(self.elems[self.arrayIdx(row, col)..]);
        }

        // TODO: Add `nth()` func to mutt.iterator.Iterator
        //  - To get specific values of the row w/out calling `next`

        /// An iterator over a row of the matrix.
        pub const Row = struct {
            mat: *Self,
            idx: usize,
            col: usize = 0,

            pub const ItemType = *T;
            pub usingnamespace mutt.iterator.Iterator(Row, ItemType);

            pub fn next(self: *Row) ?ItemType {
                if (self.col < self.mat.ncols) {
                    self.col += 1;
                    return @ptrCast(self.mat.elems[self.mat.arrayIdx(self.idx, self.col - 1)..]);
                }
                return null;
            }
        };

        /// An iterator over a column of the matrix.
        pub const Col = struct {
            mat: *Self,
            idx: usize,
            row: usize = 0,

            pub const ItemType = *T;
            pub usingnamespace mutt.iterator.Iterator(Col, ItemType);

            pub fn next(self: *Col) ?ItemType {
                if (self.row < self.mat.nrows) {
                    self.row += 1;
                    return @ptrCast(self.mat.elems[self.mat.arrayIdx(self.row - 1, self.idx)..]);
                }
                return null;
            }
        };

        /// Returns an iterator over the elements of the specified row.
        pub fn getRow(self: *Self, row: usize) !Row {
            // Input validation
            if (row >= self.nrows) {
                return Error.RowIdxOutOfBounds;
            }

            return Row{ .mat = self, .idx = row };
        }

        /// Returns an iterator over the elements of the specified column.
        pub fn getCol(self: *Self, col: usize) !Col {
            // Input validation
            if (col >= self.ncols) {
                return Error.ColIdxOutOfBounds;
            }

            return Col{ .mat = self, .idx = col };
        }

        //          Interfaces
        // ================================

        pub usingnamespace if (mutt.clone.isClone(T).valid) struct {
            pub usingnamespace mutt.clone.Clone(Self);
            pub fn clone(self: Self) Self {
                // TODO: Implement
                _ = self; // autofix
                unreachable;
            }
        } else struct {};

        usingnamespace mutt.print.Printable(Self);
        pub fn writeToBuf(self: *Self, buf: []u8) anyerror![]u8 {
            var stream = std.io.fixedBufferStream(buf);
            var writer = stream.writer();

            try writer.print("Matrix ({}x{}) [", .{ self.nrows, self.ncols });
            for (0..self.nrows) |i| {
                try writer.print("\n", .{});
                for (0..self.ncols) |j| {
                    const val = self.elems[self.arrayIdx(i, j)];
                    try writer.print(" {any} ", .{val});
                }
            }
            try writer.print("\n]", .{});
            return stream.getWritten();
        }
    };
}

const TestStructs = struct {
    const Cloneable = struct {
        const Self = @This();
        data: u8,

        pub usingnamespace mutt.clone.Clone(Self);
        pub fn clone(self: Self) Self {
            return Self{ .data = self.data + 1 };
        }
    };
};

test "init" {
    var mat = Matrix(u8).init(testing.allocator);
    defer mat.deinit();

    try testing.expectEqual(mat.nrows, 0);
    try testing.expectEqual(mat.ncols, 0);
    try testing.expectEqual(mat.capacity, 0);
}

test "initCapacity" {
    var mat = try Matrix(u8).initCapacity(testing.allocator, 2, 3);
    defer mat.deinit();

    try testing.expectEqual(mat.nrows, 0);
    try testing.expectEqual(mat.ncols, 0);
    try testing.expectEqual(mat.capacity, 6);
}

test "initFromSlice" {
    // Not cloneable
    {
        var slice = [_]u8{ 1, 2, 3, 4, 5, 6 };
        var mat = try Matrix(u8).initFromSlice(testing.allocator, &slice, 2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat.nrows, 2);
        try testing.expectEqual(mat.ncols, 3);
        try testing.expectEqual(mat.capacity, 6);
        for (mat.elems, 0..) |v, i| {
            try testing.expectEqual(slice[i], v);
        }
    }

    // Cloneable
    {
        var slice = [_]TestStructs.Cloneable{ .{ .data = 1 }, .{ .data = 2 }, .{ .data = 3 }, .{ .data = 4 }, .{ .data = 5 }, .{ .data = 6 } };
        var mat = try Matrix(TestStructs.Cloneable).initFromSlice(testing.allocator, &slice, 2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat.nrows, 2);
        try testing.expectEqual(mat.ncols, 3);
        try testing.expectEqual(mat.capacity, 6);
        for (mat.elems, 0..) |v, i| {
            try testing.expectEqual(slice[i].data + 1, v.data);
        }
    }
}

test "identity" {
    var mat = try Matrix(u8).identity(testing.allocator, 2);
    defer mat.deinit();

    try testing.expectEqual(2, mat.nrows);
    try testing.expectEqual(2, mat.ncols);
    for (0..2) |i| {
        for (0..2) |j| {
            if (i == j) {
                try testing.expectEqual(1, mat.elems[mat.arrayIdx(i, j)]);
            } else {
                try testing.expectEqual(0, mat.elems[mat.arrayIdx(i, j)]);
            }
        }
    }
}

test "get[Ptr]" {
    const slice = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var mat = try Matrix(u8).initFromSlice(testing.allocator, &slice, 2, 3);
    defer mat.deinit();

    try testing.expectEqual(slice[0], mat.get(0, 0));

    const val = try mat.getPtr(0, 0);
    val.* = 9;
    try testing.expectEqual(9, mat.get(0, 0));
}

test "getRow/Col" {
    const slice = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var mat = try Matrix(u8).initFromSlice(testing.allocator, &slice, 2, 3);
    defer mat.deinit();

    var row0 = try mat.getRow(0);
    var row0en = row0.enumerate();
    while (row0en.next()) |v| {
        try testing.expectEqual(slice[v.idx], v.val.*);
    }

    var row1 = try mat.getRow(1);
    var row1en = row1.enumerate();
    while (row1en.next()) |v| {
        try testing.expectEqual(slice[v.idx + 3], v.val.*);
    }

    var col0 = try mat.getCol(0);
    try testing.expectEqual(slice[0], col0.next().?.*);
    try testing.expectEqual(slice[3], col0.next().?.*);

    var col1 = try mat.getCol(1);
    try testing.expectEqual(slice[1], col1.next().?.*);
    try testing.expectEqual(slice[4], col1.next().?.*);

    var col2 = try mat.getCol(2);
    try testing.expectEqual(slice[2], col2.next().?.*);
    try testing.expectEqual(slice[5], col2.next().?.*);
}
