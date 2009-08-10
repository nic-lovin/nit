# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2009 Jean Privat <jean@pryen.org>
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

# Intermediate code analysis and optimizations
package analysis

import icode
import icode_dump
import allocate_iregister_slots
import inline_methods

redef class IRoutine
	# Perfom all optimizations
	fun optimize(m: MMModule)
	do
		inline_methods(m)
		allocate_iregister_slots
	end
end
