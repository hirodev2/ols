package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"

@(test)
ast_simple_struct_completion :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: My_Struct;
            my_struct.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_index_array_completion :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: [] My_Struct;
            my_struct[2].*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_pointer_completion :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: ^My_Struct;
            my_struct.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_take_address_completion :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: My_Struct;
            my_pointer := &my_struct;
            my_pointer.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_deref_completion :: proc(t: ^testing.T) {

    source := test.Source {
        main = `package test

        My_Struct :: struct {
            one: int,
            two: int,
            three: int,
        }

        main :: proc() {
            my_struct: ^^My_Struct;
            my_deref := my_struct^;
            my_deref.*
        }
        `,
        source_packages = {},
    };

    test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}


