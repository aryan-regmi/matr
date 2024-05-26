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

pub fn Matrix(comptime T: type, allocator: Allocator) type {
    return struct {
        const Self = @This();

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
        pub fn init() Self {
            return Self{
                ._data = undefined,
                ._nrows = 0,
                ._ncols = 0,
                ._capacity = 0,
            };
        }

        /// Creates a new, empty matrix with memory reserved for `nrows * ncols` elements.
        pub fn initWithCapacity(comptime nrows: usize, comptime ncols: usize) !Self {
            comptime if ((nrows == 0) or (ncols == 0)) {
                return Self.init();
            };

            const data = try allocator.alloc(T, nrows * ncols);

            return Self{
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
        pub fn initFromSlice(comptime nrows: usize, comptime ncols: usize, slice: []const T) !Self {
            // Input validation
            {
                comptime if ((nrows == 0) or (ncols == 0)) {
                    return MatrixError.InvalidSize;
                };

                if (slice.len != nrows * ncols) {
                    return MatrixError.InvalidSlice;
                }
            }

            var out = try Self.initWithCapacity(nrows, ncols);
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
        pub fn initWithValue(comptime nrows: usize, comptime ncols: usize, value: T) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init();
            }

            var data: [nrows * ncols]T = undefined;
            @memset(&data, value);
            return Self.initFromSlice(nrows, ncols, &data);
        }

        /// Creates an identity matrix of the specified size.
        pub fn identity(comptime size: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create an `identity` matrix");
            };

            var data: [size * size]T = undefined;
            @memset(&data, 0);
            var out = try Self.initFromSlice(size, size, &data);
            for (0..size) |i| {
                for (0..size) |j| {
                    if (i == j) {
                        out._data[out.arrayIdx(i, j)] = 1;
                    }
                }
            }
            return out;
        }

        /// Creates a matrix of the specified size, filled with 0.
        pub fn zeros(comptime nrows: usize, comptime ncols: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create a `zeros` matrix");
            };

            return Self.initWithValue(nrows, ncols, 0);
        }

        /// Creates a matrix of the specified size, filled with 1.
        pub fn ones(comptime nrows: usize, comptime ncols: usize) !Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The type must be numerical to create a `ones` matrix");
            };

            return Self.initWithValue(nrows, ncols, 1);
        }

        /// Frees the memory used by the matrix.
        pub fn deinit(self: *Self) void {
            if (self._capacity > 0) {
                allocator.free(self._data);
            }
            self._nrows = 0;
            self._ncols = 0;
            self._capacity = 0;
        }

        /// Gets the array index given a matrix index.
        fn arrayIdx(self: *const Self, row: usize, col: usize) usize {
            return self._ncols * row + col;
        }

        /// Returns the vaule at the specified index of the matrix.
        pub fn get(self: *const Self, row: usize, col: usize) T {
            // Input validation
            {
                if (row >= self._nrows) {
                    @panic("InvaidIndex: The row index must be less than the number of rows in the matrix");
                } else if (col >= self._ncols) {
                    @panic("InvaidIndex: The column index must be less than the number of colunns in the matrix");
                }
            }

            return self._data[self.arrayIdx(row, col)];
        }

        /// Returns a pointer to the specified index of the matrix.
        pub fn getPtr(self: *const Self, row: usize, col: usize) *T {
            // Input validation
            {
                if (row >= self._nrows) {
                    @panic("InvaidIndex: The row index must be less than the number of rows in the matrix");
                } else if (col >= self._ncols) {
                    @panic("InvaidIndex: The column index must be less than the number of colunns in the matrix");
                }
            }

            return @ptrCast(self._data[self.arrayIdx(row, col)..]);
        }
    };
}

test "Create new matrix" {
    const allocator = testing.allocator;

    // init
    {
        var mat = Matrix(i8, allocator).init();
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 0);
        try testing.expectEqual(mat._ncols, 0);
        try testing.expectEqual(mat._capacity, 0);
    }

    // initWithCapacity
    {
        var mat = try Matrix(i8, allocator).initWithCapacity(2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
    }

    // initFromSlice
    {
        var slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
        var mat = try Matrix(i8, allocator).initFromSlice(2, 3, &slice);
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data, 0..) |value, i| {
            try testing.expectEqual(value, slice[i]);
        }
    }

    // initWithValue
    {
        var mat = try Matrix(i8, allocator).initWithValue(2, 3, 5);
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data) |value| {
            try testing.expectEqual(value, 5);
        }
    }

    // identity
    {
        var mat = try Matrix(i8, allocator).identity(2);
        defer mat.deinit();

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

    // zeros
    {
        var mat = try Matrix(i8, allocator).zeros(2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data) |value| {
            try testing.expectEqual(value, 0);
        }
    }

    // ones
    {
        var mat = try Matrix(i8, allocator).ones(2, 3);
        defer mat.deinit();

        try testing.expectEqual(mat._nrows, 2);
        try testing.expectEqual(mat._ncols, 3);
        try testing.expectEqual(mat._capacity, 6);
        for (mat._data) |value| {
            try testing.expectEqual(value, 1);
        }
    }
}

test "Index matrix" {
    const allocator = testing.allocator;

    var slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
    var mat = try Matrix(i8, allocator).initFromSlice(2, 3, &slice);
    defer mat.deinit();

    const x = mat.getPtr(0, 0);
    x.* = 99;

    try testing.expectEqual(mat.get(0, 0), 99);
    try testing.expectEqual(mat.get(0, 1), 2);
    try testing.expectEqual(mat.get(0, 2), 3);
    try testing.expectEqual(mat.get(1, 0), 4);
    try testing.expectEqual(mat.get(1, 1), 5);
    try testing.expectEqual(mat.get(1, 2), 6);
}
