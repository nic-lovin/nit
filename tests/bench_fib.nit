# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2004-2008 Jean Privat <jean@pryen.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The fibbonacci program

redef class Int
	fun fib: Int
	# Unefficient recursive implementation
	do
		if self <= 0 then
			return 0
		else if self < 2 then
			return 1
		else
			return (self-1).fib + (self-2).fib
		end
	end
end

var n = 20
if not args.is_empty then
	n = args.first.to_i
end

print(n.fib)
