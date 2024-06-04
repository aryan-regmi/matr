const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const todo = unreachable;

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
/// It is recommend to use a pool/buffer as the allocator in order to make freeing temporary matricies simple.
pub fn Matrix(comptime T: type, allocator: Allocator) type {
    return struct {
        pub const Error = error{
            InvalidSize,
            InvalidSlice,
            RowIdxOutOfBounds,
            ColIdxOutOfBounds,
            InvalidRowSize,
            InvalidColSize,
            ResizeFailed,
        };

        /// Converts a `Matrix.Error` to `[]const u8`.
        pub fn errToStr(err: Error) []const u8 {
            switch (err) {
                .InvalidSize => "Invalid size: The matrix must have at least one row and column",
                .InvalidSlice => "Invalid slice: The slice must have `nrows * ncols` elements to create a valid matrix",
                .RowIdxOutOfBounds => "Index out of bounds: The row index must be less than the number of rows in the matrix",
                .ColIdxOutOfBounds => "Index out of bounds: The column index must be less than the number of columns in the matrix",
                .InvalidRowSize => "Invalid row: The row must have as many elements as the number of columns in the matrix",
                .InvalidColSize => "Invalid column: The column must have as many elements as the number of rows in the matrix",
                .ResizeFailed => "Resize failed: The matrix could not be resized successfully",
            }
        }

        const Self = @This();
        const CloneFn = ?*const fn (T) T;

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
        pub fn initWithCapacity(nrows: usize, ncols: usize) !Self {
            if ((nrows == 0) or (ncols == 0)) {
                return Self.init();
            }

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
                    return Error.InvalidSize;
                };

                if (slice.len != nrows * ncols) {
                    return Error.InvalidSlice;
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
        pub fn deinit(self: *const Self) void {
            if (self._capacity > 0) {
                allocator.free(self._data);
            }
        }

        /// Gets the array index given a matrix index.
        fn arrayIdx(self: *const Self, row: usize, col: usize) usize {
            return self._ncols * row + col;
        }

        /// Returns the vaule at the specified index of the matrix.
        pub fn get(self: *const Self, row: usize, col: usize) !T {
            // Input validation
            {
                if (row >= self._nrows) {
                    return Error.RowIdxOutOfBounds;
                } else if (col >= self._ncols) {
                    return Error.ColIdxOutOfBounds;
                }
            }

            return self._data[self.arrayIdx(row, col)];
        }

        /// Returns a pointer to the specified index of the matrix.
        pub fn getPtr(self: *const Self, row: usize, col: usize) !*T {
            // Input validation
            {
                if (row >= self._nrows) {
                    return Error.RowIdxOutOfBounds;
                } else if (col >= self._ncols) {
                    return Error.ColIdxOutOfBounds;
                }
            }

            return @ptrCast(self._data[self.arrayIdx(row, col)..]);
        }

        /// Returns a new `Matrix` containing the elements of the specified row from `self`.
        ///
        /// # Note
        /// If a type is not trivially copyable, a `clone_fn` should be provided to create a clone of the elements in `self`.
        pub fn getRow(self: *const Self, row: usize, clone_fn: CloneFn) !Self {
            // Input validation
            if (row >= self._nrows) {
                return Error.RowIdxOutOfBounds;
            }

            var out = try Self.initWithCapacity(1, self._ncols);
            out._nrows = 1;
            out._ncols = self._ncols;

            for (0..self._ncols) |col| {
                if (clone_fn != null) {
                    const elem_ptr = try out.getPtr(0, col);
                    elem_ptr.* = clone_fn.?(try self.get(row, col));
                } else {
                    const elem_ptr = try out.getPtr(0, col);
                    elem_ptr.* = try self.get(row, col);
                }
            }

            return out;
        }

        /// Returns an `ArrayList` containing pointers to the elements of the specified row in the matrix.
        ///
        /// # Note
        /// * The returned row must be freed by the caller.
        /// * The pointers in the `ArrayList` will be invalidated if the underlying matrix is freed or resized.
        pub fn getRowPtr(self: *Self, row: usize) !ArrayList(*T) {
            // Input validation
            if (row >= self._nrows) {
                return Error.RowIdxOutOfBounds;
            }

            var out = try ArrayList(*T).initCapacity(allocator, self._ncols);

            for (0..self._ncols) |col| {
                try out.append(try self.getPtr(row, col));
            }

            return out;
        }

        /// Returns a new `Matrix` containing the elements of the specified column from `self`.
        ///
        /// # Note
        /// If a type is not trivially copyable, a `clone_fn` should be provided to create a clone of the elements in `self`.
        pub fn getCol(self: *const Self, col: usize, clone_fn: CloneFn) !Self {
            // Input validation
            if (col >= self._ncols) {
                return Error.ColIdxOutOfBounds;
            }

            var out = try Self.initWithCapacity(self._nrows, 1);
            out._ncols = 1;
            out._nrows = self._nrows;

            for (0..self._nrows) |row| {
                if (clone_fn != null) {
                    const elem_ptr = try out.getPtr(row, col);
                    elem_ptr.* = clone_fn.?(try self.get(row, col));
                } else {
                    const elem_ptr = try out.getPtr(row, col);
                    elem_ptr.* = try self.get(row, col);
                }
            }

            return out;
        }

        /// Returns an `ArrayList` containing pointers to the elements of the specified column in the matrix.
        ///
        /// # Note
        /// * The returned column must be freed by the caller.
        /// * The pointers in the `ArrayList` will be invalidated if the underlying matrix is freed or resized.
        pub fn getColPtr(self: *Self, col: usize) !ArrayList(*T) {
            // Input validation
            if (col >= self._ncols) {
                return Error.ColIdxOutOfBounds;
            }

            var out = try ArrayList(*T).initCapacity(allocator, self._ncols);

            for (0..self._nrows) |row| {
                try out.append(try self.getPtr(row, col));
            }

            return out;
        }

        /// Resizes the matrix by doubling its capacity.
        fn resize(self: *Self, clone_fn: CloneFn) !void {
            // Allocate new array
            var new_cap = self._capacity * 2;
            if ((self._nrows == 0) and (self._ncols == 0)) {
                new_cap = 2;
            } else if (self._nrows == 0) {
                new_cap = self._ncols * 2;
            } else if (self._ncols == 0) {
                new_cap = self._nrows * 2;
            }
            const resized = try allocator.alloc(T, new_cap);

            // Copy old values
            for (0..self._nrows * self._ncols) |i| {
                if (clone_fn != null) {
                    resized[i] = clone_fn.?(self._data[i]);
                } else {
                    resized[i] = self._data[i];
                }
            }

            // Free old array & replace w/ resized
            allocator.free(self._data);
            self._data = resized;
            self._capacity = new_cap;
        }

        /// Sets the row at the specified index to the given `row`.
        pub fn setRow(self: *Self, idx: usize, row: []const T, clone_fn: CloneFn) !void {
            // Input validation
            {
                if (idx >= self._nrows) {
                    return Error.RowIdxOutOfBounds;
                }
                if (row.len != self._ncols) {
                    return Error.InvalidRowSize;
                }
            }

            for (0..self._ncols) |col| {
                const elem_ptr = try self.getPtr(idx, col);
                if (clone_fn != null) {
                    elem_ptr.* = clone_fn.?(row[col]);
                } else {
                    elem_ptr.* = row[col];
                }
            }
        }

        /// Appends the given row to the end of the matrix.
        ///
        /// # Note
        /// The row must have `self._ncols` number of elements.
        pub fn pushRow(self: *Self, row: []const T, clone_fn: CloneFn) !void {
            // Input validation
            {
                if (self._ncols == 0) {
                    self._ncols = row.len;
                } else if (row.len != self._ncols) {
                    return Error.InvalidRowSize;
                }
            }

            // Resize if necessary
            if (self._capacity < (self._nrows + 1) * self._ncols) {
                self.resize(clone_fn) catch return Error.ResizeFailed;
            }

            // Push the values from the row
            self._nrows += 1;
            try self.setRow(self._nrows - 1, row, clone_fn);
        }

        /// Sets the row at the specified index to the given `row`.
        pub fn setCol(self: *Self, idx: usize, col: []const T, clone_fn: CloneFn) !void {
            // Input validation
            {
                if (idx >= self._ncols) {
                    return Error.ColIdxOutOfBounds;
                }
                if (col.len != self._nrows) {
                    return Error.InvalidColSize;
                }
            }

            for (0..self._nrows) |row| {
                const elem_ptr = try self.getPtr(row, idx);
                if (clone_fn != null) {
                    elem_ptr.* = clone_fn.?(col[row]);
                } else {
                    elem_ptr.* = col[row];
                }
            }
        }

        /// Appends the given column to the end of the matrix.
        ///
        /// # Note
        /// The column must have `self._nrows` number of elements.
        pub fn pushCol(self: *Self, col: []const T, clone_fn: CloneFn) !void {
            // Input validation
            {
                if (self._nrows == 0) {
                    self._nrows = col.len;
                } else if (col.len != self._nrows) {
                    return Error.InvalidColSize;
                }
            }

            // Resize if necessary
            if (self._capacity < self._nrows * (self._ncols + 1)) {
                self.resize(clone_fn) catch return Error.ResizeFailed;
            }

            // Push the values from the row
            self._ncols += 1;
            try self.setCol(self._ncols - 1, col, clone_fn);
        }

        pub fn scale(self: *const Self, scalar: T) !Self {
            _ = scalar; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn addElems(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn subElems(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn mul(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn mulElems(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn leftDiv(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn rightDiv(self: *const Self, other: *const Self) !Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        pub fn inverse(self: *const Self) !Self {
            _ = self; // autofix
            todo;
        }

        pub fn transpose(self: *const Self) !Self {
            _ = self; // autofix
            todo;
        }

        // TODO: Add in-place versions where possible
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

    const x = try mat.getPtr(0, 0);
    x.* = 99;

    try testing.expectEqual(try mat.get(0, 0), 99);
    try testing.expectEqual(try mat.get(0, 1), 2);
    try testing.expectEqual(try mat.get(0, 2), 3);
    try testing.expectEqual(try mat.get(1, 0), 4);
    try testing.expectEqual(try mat.get(1, 1), 5);
    try testing.expectEqual(try mat.get(1, 2), 6);
}

test "Get rows" {
    const allocator = testing.allocator;

    var slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
    var mat = try Matrix(i8, allocator).initFromSlice(2, 3, &slice);
    defer mat.deinit();

    const row0 = try mat.getRow(0, null);
    defer row0.deinit();
    for (row0._data, 0..) |value, i| {
        try testing.expectEqual(value, slice[i]);
    }

    const row0_ptr = try mat.getRowPtr(0);
    defer row0_ptr.deinit();
    for (row0_ptr.items, 0..) |value, i| {
        value.* += 20;
        try testing.expectEqual(try mat.get(0, i), value.*);
    }
    for (row0._data, 0..) |value, i| {
        try testing.expectEqual(value, slice[i]);
    }
}

test "Get cols" {
    const allocator = testing.allocator;

    var slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
    var mat = try Matrix(i8, allocator).initFromSlice(2, 3, &slice);
    defer mat.deinit();

    const col0 = try mat.getCol(0, null);
    defer col0.deinit();
    for (col0._data, 0..) |value, i| {
        if (i == 0) {
            try testing.expectEqual(value, slice[0]);
        } else {
            try testing.expectEqual(value, slice[3]);
        }
    }

    const col0_ptr = try mat.getColPtr(0);
    defer col0_ptr.deinit();
    for (col0_ptr.items, 0..) |value, i| {
        value.* += 20;
        try testing.expectEqual(try mat.get(i, 0), value.*);
    }
    for (col0._data, 0..) |value, i| {
        if (i == 0) {
            try testing.expectEqual(value, slice[0]);
        } else {
            try testing.expectEqual(value, slice[3]);
        }
    }
}

test "Push rows and cols" {
    const allocator = testing.allocator;

    var mat = Matrix(i8, allocator).init();
    defer mat.deinit();

    var slice = [_]i8{ 1, 2, 3 };
    try mat.pushRow(&[_]i8{ 1, 2, 3 }, null);

    const row = try mat.getRowPtr(0);
    defer row.deinit();
    for (row.items, 0..) |value, i| {
        try testing.expectEqual(value.*, slice[i]);
    }

    slice = [_]i8{ 4, 5, 6 };
    try mat.pushRow(&[_]i8{ 4, 5, 6 }, null);
    const row2 = try mat.getRowPtr(1);
    defer row2.deinit();
    for (row2.items, 0..) |value, i| {
        try testing.expectEqual(value.*, slice[i]);
    }

    const slice2 = [_]i8{ 7, 8 };
    try mat.pushCol(&[_]i8{ 7, 8 }, null);
    const col = try mat.getColPtr(3);
    defer col.deinit();
    for (col.items, 0..) |value, i| {
        try testing.expectEqual(value.*, slice2[i]);
    }
}
