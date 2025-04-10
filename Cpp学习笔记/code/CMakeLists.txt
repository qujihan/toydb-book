cmake_minimum_required(VERSION 3.21)
project(code
        DESCRIPTION "C++学习笔记"
        LANGUAGES CXX
)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)

include(src)