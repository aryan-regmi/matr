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

// TODO: Add examples to function docs
//
// TODO: Add clone method
//
// TODO: Add in-place versions where possible

/// Represents the range `[start, end)`.
pub const Range = struct {
    /// The start index of the range.
    start: usize,

    /// The end index of the range.
    end: usize,
};

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
        pub fn getPtr(self: *Self, row: usize, col: usize) !*T {
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
            const new_cap: usize = calc_cap: {
                if ((self._nrows == 0) and (self._ncols == 0)) {
                    break :calc_cap 2;
                } else if (self._nrows == 0) {
                    break :calc_cap self._ncols * 2;
                } else if (self._ncols == 0) {
                    break :calc_cap self._nrows * 2;
                } else {
                    break :calc_cap self._capacity * 2;
                }
            };
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

            for (1..col.len + 1) |i| {
                // Shift everything after the insert index to the right
                const idx = self._ncols * i + (i - 1);
                const nshifted = self._ncols * self._nrows - self._ncols * i;
                const src = self._data[idx..];
                const dst = self._data[idx + 1 ..];
                const tmp = try allocator.alloc(T, nshifted);
                defer allocator.free(tmp);
                @memcpy(tmp, src[0..nshifted]);
                for (0..nshifted) |n| {
                    dst[n] = tmp[n];
                }

                // Update index w/ value from `col`
                self._data[idx] = col[i - 1];
            }

            self._ncols += 1;
        }

        /// Returns a new matrix containing each element of `self` multiplied by the `scalar`.
        ///
        /// # Note
        /// The scalar must be a numerical type (i.e int or float).
        pub fn scale(self: *const Self, scalar: T) Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The matrix must be scaled by a numerical type");
            };

            var out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] * scalar;
            }

            return out;
        }

        /// Returns a new matrix containing the result of element-wise addition of `self` and `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn addElems(self: *const Self, other: *const Self) Self {
            // Input validation
            {
                comptime if (isNumber(T) == false) {
                    @compileError("Invalid type: The matrix must be scaled by a numerical type");
                };

                if ((self._nrows != other._nrows) or (self._ncols != other._ncols)) {
                    @panic(errToStr(Error.InvalidDimensions));
                }
            }

            const out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] + other._data[i];
            }

            return out;
        }

        /// Returns a new matrix containing `scalar` added to each element of `self`.
        ///
        /// # Note
        /// The scalar must be a numerical type (i.e int or float).
        pub fn addScalar(self: *const Self, scalar: T) Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The matrix must be scaled by a numerical type");
            };

            var out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] + scalar;
            }

            return out;
        }

        /// Returns a new matrix containing `scalar` subtracted from to each element of `self`.
        ///
        /// # Note
        /// The scalar must be a numerical type (i.e int or float).
        pub fn subScalar(self: *const Self, scalar: T) Self {
            // Input validation
            comptime if (isNumber(T) == false) {
                @compileError("Invalid type: The matrix must be scaled by a numerical type");
            };

            var out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] - scalar;
            }

            return out;
        }

        /// Returns a new matrix containing the result of element-wise subtraction of `self` and `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn subElems(self: *const Self, other: *const Self) Self {
            // Input validation
            {
                comptime if (isNumber(T) == false) {
                    @compileError("Invalid type: The matrix must be scaled by a numerical type");
                };

                if ((self._nrows != other._nrows) or (self._ncols != other._ncols)) {
                    @panic(errToStr(Error.InvalidDimensions));
                }
            }

            const out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] - other._data[i];
            }

            return out;
        }

        /// Returns a new matrix containing the result of element-wise multiplication of `self` and `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn mul(self: *const Self, other: *const Self) Self {
            // Input validation
            {
                comptime if (isNumber(T) == false) {
                    @compileError("Invalid type: The matricies must contain a numerical type (int or float)");
                };

                if (self._ncols != other._nrows) {
                    @panic(errToStr(Error.InvalidMulDimensions));
                }
            }

            var out = Self.initWithCapacity(self._nrows, other._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows) |i| {
                for (0..other._ncols) |j| {
                    var sum: T = 0;
                    for (0..self._ncols) |k| {
                        sum += self._data[self.arrayIdx(i, k)] * other._data[other.arrayIdx(k, j)];
                    }
                    out._data[out.arrayIdx(i, j)] = sum;
                }
            }

            return out;
        }

        /// Returns a new matrix containing the result of element-wise multiplication of `self` and `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn mulElems(self: *const Self, other: *const Self) Self {
            // Input validation
            {
                comptime if (isNumber(T) == false) {
                    @compileError("Invalid type: The matricies must contain a numerical type (int or float)");
                };

                if ((self._nrows != other._nrows) or (self._ncols != other._ncols)) {
                    @panic(errToStr(Error.InvalidDimensions));
                }
            }

            var out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            for (0..self._nrows * self._ncols) |i| {
                out._data[i] = self._data[i] * other._data[i];
            }

            return out;
        }

        /// Returns a new matrix containing the result of left matrix division of `self` by `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn leftDiv(self: *const Self, other: *const Self) Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        /// Returns a new matrix containing the result of right matrix division of `self` by `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn rightDiv(self: *const Self, other: *const Self) Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        /// Returns a new matrix containing the result of element-wise division of `self` by `other`.
        ///
        /// # Note
        /// The type `T` must be a numerical type (i.e int or float).
        pub fn divElems(self: *const Self, other: *const Self) Self {
            _ = other; // autofix
            _ = self; // autofix
            todo;
        }

        /// Returns a new matrix containing the inverse of `self`, if one exists.
        pub fn inverse(self: *const Self) Self {
            _ = self; // autofix
            todo;
        }

        /// Returns a new matrix containing the transpose of `self`.
        pub fn transpose(self: *const Self) Self {
            var out = Self.initWithCapacity(self._nrows, self._ncols) catch @panic(errToStr(Error.InitFailed));
            out._nrows = self._ncols;
            out._ncols = self._nrows;

            for (0..self._nrows) |i| {
                for (0..self._ncols) |j| {
                    out._data[out.arrayIdx(j, i)] = self._data[self.arrayIdx(i, j)];
                }
            }

            return out;
        }

        /// Calculates the Euclidean norm of the matrix.
        pub fn norm(self: *const Self) f32 {
            // Input validation
            {
                comptime if (isNumber(T) == false) {
                    @compileError("Invalid type: The matricies must contain a numerical type (int or float)");
                };
            }
            var out: f32 = 0;
            for (0..self._nrows) |i| {
                for (0..self._ncols) |j| {
                    out += std.math.powi(f32, @floatCast(self.get(i, j)), 2) catch |err| {
                        switch (err) {
                            .Overflow => @panic("Overflow occured"),
                            .Underflow => @panic("Underflow occured"),
                        }
                    };
                }
            }
            return std.math.sqrt(out);
        }

        /// Returns a sub-matrix of `self`.
        pub fn submatrix(self: *const Self, rows: Range, cols: Range) !Self {
            _ = self; // autofix

            const row_rev = rows.start > rows.end;
            _ = row_rev; // autofix
            const col_rev = cols.start > cols.end;
            _ = col_rev; // autofix

            todo;

            // // Input validation
            // if (row >= self._nrows) {
            //     return Error.RowIdxOutOfBounds;
            // }
            //
            // var out = try Self.initWithCapacity(1, self._ncols);
            // out._nrows = 1;
            // out._ncols = self._ncols;
            //
            // for (0..self._ncols) |col| {
            //     if (clone_fn != null) {
            //         const elem_ptr = try out.getPtr(0, col);
            //         elem_ptr.* = clone_fn.?(try self.get(row, col));
            //     } else {
            //         const elem_ptr = try out.getPtr(0, col);
            //         elem_ptr.* = try self.get(row, col);
            //     }
            // }
            //
            // return out;

        }

        /// Returns `true` if the matrix is square (equal number of rows and columns).
        pub fn isSquare(self: *const Self) bool {
            return self._nrows == self._ncols;
        }

        /// Returns `true` if the matrix is an upper triangular.
        pub fn isTriangularUpper(self: *const Self) bool {
            _ = self; // autofix
            todo;
        }

        /// Returns `true` if the matrix is a lower triangular.
        pub fn isTriangularLower(self: *const Self) bool {
            _ = self; // autofix
            todo;
        }

        /// Calculates the QR factorization/decomposition of `self` using Householder transformations.
        pub fn qr(self: *const Self) Self {
            _ = self; // autofix
            todo;
        }

        /// Calculates the LU factorization/decomposition of `self`.
        pub fn lu(self: *const Self) Self {
            _ = self; // autofix
            todo;
        }

        /// Returns the number of rows in the matrix.
        pub fn numRows(self: *const Self) usize {
            return self._nrows;
        }

        /// Returns the number of columns in the matrix.
        pub fn numCols(self: *const Self) usize {
            return self._ncols;
        }

        /// Returns an immutable slice of the elements in `self`.
        pub fn elements(self: *const Self) []const T {
            return self._data;
        }

        // TODO: Replace tmp w/ bufPrint instead! (Don't create ArrayList)
        //
        /// Returns a string representation of the matrix.
        pub fn toString(self: *const Self, buf: []u8) ![]u8 {
            var tmp = ArrayList(u8).init(allocator);
            defer tmp.deinit();

            try tmp.writer().print("Matrix ({any}x{any}) [", .{ self._nrows, self._ncols });
            for (0..self._nrows) |i| {
                try tmp.writer().print("\n", .{});
                for (0..self._ncols) |j| {
                    const val = try self.get(i, j);
                    try tmp.writer().print(" {any} ", .{val});
                }
            }
            try tmp.writer().print("\n]", .{});

            @memcpy(buf[0..tmp.items.len], tmp.items);
            return buf[0..tmp.items.len];
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

    // var buf: [100]u8 = undefined;
    // const str = try mat.toString(&buf);
    // std.log.warn("mat: {s}", .{str});
}

test "Math" {
    const allocator = testing.allocator;

    const slice = [_]i8{ 1, 2, 3, 4, 5, 6 };
    const mat = try Matrix(i8, allocator).initFromSlice(2, 3, &slice);
    defer mat.deinit();

    // Scale
    {
        const scaled = mat.scale(2);
        defer scaled.deinit();
        for (scaled.elements(), 0..) |value, i| {
            try testing.expectEqual(slice[i] * 2, value);
        }
    }

    // Add elems
    {
        const added_elems = mat.addElems(&mat);
        defer added_elems.deinit();
        for (added_elems.elements(), mat.elements()) |value, old_value| {
            try testing.expectEqual(old_value * 2, value);
        }
    }

    // Add scalar
    {
        const added_scalar = mat.addScalar(1);
        defer added_scalar.deinit();
        for (added_scalar.elements(), mat.elements()) |value, old_value| {
            try testing.expectEqual(old_value + 1, value);
        }
    }

    // Sub scalar
    {
        const sub_scalar = mat.subScalar(1);
        defer sub_scalar.deinit();
        for (sub_scalar.elements(), mat.elements()) |value, old_value| {
            try testing.expectEqual(old_value - 1, value);
        }
    }

    // Sub elems
    {
        const sub_elems = mat.subElems(&mat);
        defer sub_elems.deinit();
        for (sub_elems.elements()) |value| {
            try testing.expectEqual(0, value);
        }
    }

    // Mul
    {
        const transpose = mat.transpose();
        defer transpose.deinit();
        const mul = mat.mul(&transpose);
        defer mul.deinit();
        const result = [_]i8{ 14, 32, 32, 77 };
        for (mul.elements(), 0..) |value, i| {
            try testing.expectEqual(result[i], value);
        }
    }

    // Mul elems
    {
        const mul_elems = mat.mulElems(&mat);
        defer mul_elems.deinit();
        const result = [_]i8{ 1, 4, 9, 16, 25, 36 };
        for (mul_elems.elements(), 0..) |value, i| {
            try testing.expectEqual(result[i], value);
        }
    }
}
