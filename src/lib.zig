const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

fn Matrix(comptime T: type) type {
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
        fn init(allocator: Allocator) Self {
            return Self{
                ._allocator = allocator,
                ._data = undefined,
                ._nrows = 0,
                ._ncols = 0,
                ._capacity = 0,
            };
        }

        /// Creates a new, empty matrix with memory reserved for `nrows * ncols` elements.
        fn initWithCapacity(allocator: Allocator, nrows: usize, ncols: usize) !Self {
            const data = try allocator.alloc(T, nrows * ncols);

            return Self{
                ._allocator = allocator,
                ._data = data,
                ._nrows = nrows,
                ._ncols = ncols,
                ._capacity = nrows * ncols,
            };
        }

        /// Frees the memory used by the matrix.
        fn deinit(self: *Self) void {
            if (self._capacity > 0) {
                self._allocator.free(self._data);
            }
            self._nrows = 0;
            self._ncols = 0;
            self._capacity = 0;
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
}
