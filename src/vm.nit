# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2014 Julien Pagès <julien.pages@lirmm.fr>
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

# Implementation of the Nit virtual machine
module vm

intrude import naive_interpreter
import model_utils
import perfect_hashing

redef class ModelBuilder
	redef fun run_naive_interpreter(mainmodule: MModule, arguments: Array[String])
	do
		var time0 = get_time
		self.toolcontext.info("*** NITVM STARTING ***", 1)

		var interpreter = new VirtualMachine(self, mainmodule, arguments)
		init_naive_interpreter(interpreter, mainmodule)

		var time1 = get_time
		self.toolcontext.info("*** NITVM STOPPING : {time1-time0} ***", 2)
	end
end

# A virtual machine based on the naive_interpreter
class VirtualMachine super NaiveInterpreter

	# Perfect hashing and perfect numbering
	var ph: Perfecthashing = new Perfecthashing

	# Handles memory and garbage collection
	var memory_manager: MemoryManager = new MemoryManager

	# Subtyping test for the virtual machine
	redef fun is_subtype(sub, sup: MType): Bool
	do
		var anchor = self.frame.arguments.first.mtype.as(MClassType)
		var sup_accept_null = false
		if sup isa MNullableType then
			sup_accept_null = true
			sup = sup.mtype
		else if sup isa MNullType then
			sup_accept_null = true
		end

		# Can `sub` provides null or not?
		# Thus we can match with `sup_accept_null`
		# Also discard the nullable marker if it exists
		if sub isa MNullableType then
			if not sup_accept_null then return false
			sub = sub.mtype
		else if sub isa MNullType then
			return sup_accept_null
		end
		# Now the case of direct null and nullable is over

		# An unfixed formal type can only accept itself
		if sup isa MParameterType or sup isa MVirtualType then
			return sub == sup
		end
		
		if sub isa MParameterType or sub isa MVirtualType then
			sub = sub.anchor_to(mainmodule, anchor)
			# Manage the second layer of null/nullable
			if sub isa MNullableType then
				if not sup_accept_null then return false
				sub = sub.mtype
			else if sub isa MNullType then
				return sup_accept_null
			end
		end

		assert sub isa MClassType

		# `sup` accepts only null
		if sup isa MNullType then return false

		assert sup isa MClassType

		# Create the sup vtable if not create
		if not sup.mclass.loaded then create_class(sup.mclass)

		# Sub can be discovered inside a Generic type during the subtyping test
		if not sub.mclass.loaded then create_class(sub.mclass)

		if anchor == null then anchor = sub
		if sup isa MGenericType then
			var sub2 = sub.supertype_to(mainmodule, anchor, sup.mclass)
			assert sub2.mclass == sup.mclass

			for i in [0..sup.mclass.arity[ do
				var sub_arg = sub2.arguments[i]
				var sup_arg = sup.arguments[i]
				var res = is_subtype(sub_arg, sup_arg)

				if res == false then return false
			end
			return true
		end

		var super_id = sup.mclass.vtable.id
		var mask = sub.mclass.vtable.mask

		return inter_is_subtype(super_id, mask, sub.mclass.vtable.internal_vtable)
	end

	# Subtyping test with perfect hashing
	private fun inter_is_subtype(id: Int, mask:Int, vtable: Pointer): Bool `{
		// hv is the position in hashtable
		int hv = id & mask;

		// Follow the pointer to somewhere in the vtable
		long unsigned int *offset = (long unsigned int*)(((long int *)vtable)[-hv]);
		
		// If the pointed value is corresponding to the identifier, the test is true, otherwise false
		return *offset == id;
	`}
	
	# Redef init_instance to simulate the loading of a class
	redef fun init_instance(recv: Instance)
	do
		if not recv.mtype.as(MClassType).mclass.loaded then create_class(recv.mtype.as(MClassType).mclass)
		super

		recv.vtable = recv.mtype.as(MClassType).mclass.vtable
	end
	
	# Creates the runtime structures for this class
	fun create_class(mclass: MClass) do	mclass.make_vt(self)
end

redef class MClass
	# A reference to the virtual table of this class
	var vtable: nullable VTable

	# True when the class is effectively loaded by the vm, false otherwise
	var loaded: Bool = false

	# Allocates a VTable for this class and gives it an id
	private fun make_vt(v: VirtualMachine)
	do
		if loaded then return

		# Superclasses contains all superclasses except self
		var superclasses = new Array[MClass]
		superclasses.add_all(ancestors)
		superclasses.remove(self)
		v.mainmodule.linearize_mclasses(superclasses)

		# Make_vt for super-classes
		var ids = new Array[Int]
		var nb_methods = new Array[Int]

		for parent in superclasses do
			if parent.vtable == null then parent.make_vt(v)
			
			# Get the number of introduced methods for this class
			var count = 0
			var min_visibility = public_visibility
			for p in parent.intro_mproperties(min_visibility) do
				if p isa MMethod then
					count += 1
				end
			end
			
			ids.push(parent.vtable.id)
			nb_methods.push(count)
		end
		
		# When all super-classes have their identifiers and vtables, allocate current one
		allocate_vtable(v, ids, nb_methods)
		loaded = true
		# The virtual table now needs to be filled with pointer to methods
	end

	# Allocate a single vtable
	# 	ids : Array of superclasses identifiers
	# 	nb_methods : Array which contain the number of methods for each class in ids
	private fun allocate_vtable(v: VirtualMachine, ids: Array[Int], nb_methods: Array[Int])
	do
		vtable = new VTable
		var idc = new Array[Int]

		vtable.mask = v.ph.pnand(ids, 1, idc) - 1
		vtable.id = idc[0]
		vtable.classname = name

		# Add current id to Array of super-ids
		var ids_total = new Array[Int]
		ids_total.add_all(ids)
		ids_total.push(vtable.id)

		var nb_methods_total = new Array[Int]
		var count = 0
		var min_visibility = public_visibility
		for p in intro_mproperties(min_visibility) do
			if p isa MMethod then
				count += 1
			end
		end
		nb_methods_total.add_all(nb_methods)
		nb_methods_total.push(count)
		
		vtable.internal_vtable = v.memory_manager.init_vtable(ids_total, nb_methods_total, vtable.mask)
	end
end

# A VTable contains the virtual method table for the dispatch
# and informations to perform subtyping tests
class VTable
	# The mask to perform perfect hashing
	var mask: Int

	# Unique identifier given by perfect hashing
	var id: Int

	# Pointer to the c-allocated area, represents the virtual table
	var internal_vtable: Pointer

	# The short classname of this class
	var classname: String

	init do end
end

redef class Instance
	
	var vtable: nullable VTable

	init(mt: MType)
	do
		mtype = mt

		# An instance is associated to its class virtual table
		if mt isa MClassType then
			vtable = mt.mclass.vtable
		end
	end
end

# Handle memory, used for allocate virtual table and associated structures
class MemoryManager

	# Allocate and fill a virtual table
	fun init_vtable(ids: Array[Int], nb_methods: Array[Int], mask: Int): Pointer 
	do
		# Allocate in C current virtual table
		var res = intern_init_vtable(ids, nb_methods, mask)

		return res
	end

	# Construct virtual tables with a bi-dimensional layout
	private fun intern_init_vtable(ids: Array[Int], nb_methods: Array[Int], mask: Int): Pointer 
		import Array[Int].length, Array[Int].[] `{

		// Allocate and fill current virtual table
		int i;
		int total_size = 0; // total size of this virtual table
		int nb_classes = Array_of_Int_length(nb_methods);
		for(i = 0; i<nb_classes; i++) {
			/* - One for each method of this class
			*  - One for the delta (pointer to attributes)
			*  - One for the id 
			*/
			total_size += Array_of_Int__index(nb_methods, i);
			total_size += 2;
		}

		// And the size of the perfect hashtable
		total_size += mask+1;
		long unsigned int* vtable = malloc(sizeof(long unsigned int)*total_size);
		
		// Initialisation to the first position of the virtual table (ie : Object)
		long unsigned int *init = vtable + mask + 2;
		for(i=0; i<total_size; i++)
			vtable[i] = (long unsigned int)init;

		// Set the virtual table to its position 0 
		// ie: after the hashtable
		vtable = vtable + mask + 1;
		
		int current_size = 1;
		for(i = 0; i < nb_classes; i++) {
			/*
				vtable[hv] contains a pointer to the group of introducted methods
				For each superclasse we have in virtual table :
					(id | delta (attributes) | introduced methods)
			*/
			int hv = mask & Array_of_Int__index(ids, i);

			vtable[current_size] = Array_of_Int__index(ids, i);
			vtable[-hv] = (long unsigned int)&(vtable[current_size]);
			
			current_size += 2;
			current_size += Array_of_Int__index(nb_methods, i);
		}

		return vtable;
	`}
end