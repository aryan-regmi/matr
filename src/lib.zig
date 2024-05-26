const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// Checks if a type is a number.
fn isNumber(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => return true,
        else => return false,
    }
}

pub const MatrixError = error{
    InvalidSize,
    InvalidSlice,
    InvalidType,
};

pub fn Matrix(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Allocator used for memory management.
        _allocator: Allocator,

        /// The elements of the matrix.
        _data: []T,

        /// Number of rows in the matrix.
        _nrows: usize,

        /// Number of columns in the matrix.
        _ncols: usize,

        /// Number of elements reserved for the matrix.
        _capacity: usize,

        /// Creates a new, empty matrix.
        ///
        /// # Note
        /// Nothing is allocated until the first push.
        pub fn init(allocator: Allocator) Self {
            return Self{
                ._allocator = allocator,
                ._data = undefined,
                ._nrows = 0,
                ._ncols = 0,
                ._capacity = 0,
            };
        }

        /// Creates a new, empty matrix with memory reserved for `nrows * ncols` elements.
        pub fn initWithCapacity(allocator: Allocator, nrows: usize, ncols: usize) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init(allocator);
            }

            const data = try allocator.alloc(T, nrows * ncols);

            return Self{
                ._allocator = allocator,
                ._data = data,
                ._nrows = nrows,
                ._ncols = ncols,
                ._capacity = nrows * ncols,
            };
        }

        /// Creates a new matrix from the given slice.
        ///
        /// # Note
        /// The slice must have `nrows * ncols` elements, and the number of rows and columns must be at least 1.
        pub fn initFromSlice(allocator: Allocator, nrows: usize, ncols: usize, slice: []const T) !Self {
            // Input validation
            {
                if ((nrows == 0) or (ncols == 0)) {
                    return MatrixError.InvalidSize;
                }

                if (slice.len != nrows * ncols) {
                    return MatrixError.InvalidSlice;
                }
            }

            var out = try Self.initWithCapacity(allocator, nrows, ncols);
            out._nrows = nrows;
            out._ncols = ncols;
            for (0..nrows) |i| {
                for (0..ncols) |j| {
                    out._data[out.arrayIdx(i, j)] = slice[out.arrayIdx(i, j)];
                }
            }
            return out;
        }

        /// Creates a new matrix of the specified size, with all elements set to `value`.
        pub fn initWithValue(allocator: Allocator, comptime nrows: usize, comptime ncols: usize, value: T) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init(allocator);
            }

            var data: [nrows * ncols]T = undefined;
            @memset(&data, value);
            return Self.initFromSlice(allocator, nrows, ncols, &data);
        }

        pub fn identity(allocator: Allocator, comptime size: usize) !Self {
            if (isNumber(T) == false) {
                return MatrixError.InvalidType;
            }

            var data: [size * size]T = undefined;
            @memset(&data, 0);
            var out = try Self.initFromSlice(allocator, size, size, &data);
            for (0..size) |i| {
                for (0..size) |j| {
                    if (i == j) {
                        out._data[out.arrayIdx(i, j)] = 1;
                    }
                }
            }
            return out;
        }

        /// Frees the memory used by the matrix.
        pub fn deinit(self: *Self) void {
            if (self._capacity > 0) {
                self._allocator.free(self._data);
            }
            self._nrows = 0;
            self._ncols = 0;
            self._capacity = 0;
        }

        /// Gets the array index given a matrix index.
        fn arrayIdx(self: *const Self, row: usize, col: usize) usize {
            return self._ncols * row + col;
        }
    };
}

test "Create new Matrix" {
    const allocator = testing.allocator;

    // init
    {
        var mat = Matrix(i8).init(allocator);
        defer mat.deinit();

        try testing.expectEqual(mat._allocator, allocator);
        try testing.expectEqual(mat._nrows, 0);
        try testing.expectEqual(mat._ncols, 0);
        try testing.expectEqual(mat._capacity, 0);
    }

    // initWithCapacity
    {
        var mat = try Matrix(i8).initWithCapacity(allocator, 2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat._allocator, allocator);
        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
    }

    // initFromSlice
    {
        var slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
        var mat = try Matrix(i8).initFromSlice(allocator, 2, 3, &slice);
        defer mat.deinit();

        try testing.expectEqual(mat._allocator, allocator);
        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data, 0..) |value, i| {
            try testing.expectEqual(value, slice[i]);
        }
    }

    // initWithValue
    {
        var mat = try Matrix(i8).initWithValue(allocator, 2, 3, 5);
        defer mat.deinit();

        try testing.expectEqual(mat._allocator, allocator);
        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data) |value| {
            try testing.expectEqual(value, 5);
        }
    }

    // identity
    {
        var mat = try Matrix(i8).identity(allocator, 2);
        defer mat.deinit();

        try testing.expectEqual(mat._allocator, allocator);
        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 2);
        try testing.expectEqual(mat._capacity, 4);
        for (0..2) |i| {
            for (0..2) |j| {
                if (i == j) {
                    try testing.expectEqual(mat._data[mat.arrayIdx(i, j)], 1);
                } else {
                    try testing.expectEqual(mat._data[mat.arrayIdx(i, j)], 0);
                }
            }
        }
    }
}
