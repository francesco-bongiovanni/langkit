with Langkit_Support.Array_Utils;

package body Langkit_Support.Lexical_Env is

   package Env_Element_Arrays is new Langkit_Support.Array_Utils
     (Env_Element, Positive, Env_Element_Array);

   procedure Inc_Ref (Self : Env_Getter);
   procedure Dec_Ref (Self : in out Env_Getter);
   --  Helpers for Env_Getters. TODO: To be removed when we remove ref-counting
   --  from lexical envs.

   function Decorate
     (Els              : Env_Element_Array;
      MD               : Element_Metadata;
      Parents_Bindings : Env_Rebindings) return Env_Element_Array;
   --  From an array of Env_Elements, decorate every element with additional
   --  Metadata stored in MD.

   ------------
   -- Create --
   ------------

   function Create
      (El : Element_T; MD : Element_Metadata) return Env_Element
   is
   begin
      return Env_Element'
        (El => El, MD => MD, Parents_Bindings => <>, Is_Null => False);
   end Create;

   ------------
   -- Unwrap --
   ------------

   function Unwrap
     (Els : Env_Element_Array) return Element_Array
   is
      function Get (Self : Env_Element) return Element_T is (Self.El)
        with Inline;

      function Internal_Unwrap is new Env_Element_Arrays.Map_Gen
        (Element_T, Element_Array, Get)
        with Inline;
      --  Internal_Unwrap could be exposed directly, but in order to have a
      --  full subprogram profile available to the users, we wrap the generic
      --  instantiation.

   begin
      return Internal_Unwrap (Els);
   end Unwrap;

   --------------
   -- Decorate --
   --------------

   function Decorate
     (Els              : Env_Element_Array;
      MD               : Element_Metadata;
      Parents_Bindings : Env_Rebindings) return Env_Element_Array
   is
      function Decorate_Element (El : Env_Element) return Env_Element
      is
        (Env_Element'
           (El.El,
            Combine (El.MD, MD),
            Parents_Bindings =>
               Combine (El.Parents_Bindings, Parents_Bindings),
            Is_Null          => False));

      function Internal_Decorate
      is new Env_Element_Arrays.Id_Map_Gen (Decorate_Element)
        with Inline;
   begin
      return Internal_Decorate (Els);
   end Decorate;

   ------------
   -- Create --
   ------------

   function Create
     (Parent        : Env_Getter;
      Node          : Element_T;
      Is_Refcounted : Boolean;
      Default_MD    : Element_Metadata := Empty_Metadata) return Lexical_Env
   is
   begin
      if Parent /= No_Env_Getter then
         Inc_Ref (Parent);
      end if;
      return new Lexical_Env_Type'
        (Parent          => Parent,
         Node            => Node,
         Referenced_Envs => <>,
         Transitive_Referenced_Envs => <>,
         Env             => new Internal_Envs.Map,
         Default_MD                 => Default_MD,
         Parents_Rebindings         => null,
         Ref_Count       => (if Is_Refcounted then 1 else No_Refcount));
   end Create;

   ---------
   -- Add --
   ---------

   procedure Add
     (Self  : Lexical_Env;
      Key   : Symbol_Type;
      Value : Element_T;
      MD    : Element_Metadata := Empty_Metadata)
   is
      use Internal_Envs;

      Env_El : constant Env_Element :=
        Env_Element'(Value, MD, null, False);
      C      : Cursor;
      Dummy  : Boolean;
   begin
      --  See Empty_Env's documentation

      if Self = Empty_Env then
         return;
      end if;

      Self.Env.Insert (Key, Env_Element_Vectors.Empty_Vector, C, Dummy);
      Append (Reference (Self.Env.all, C).Element.all, Env_El);
   end Add;

   ------------
   -- Remove --
   ------------

   procedure Remove
     (Self  : Lexical_Env;
      Key   : Symbol_Type;
      Value : Element_T)
   is
      V : constant Internal_Envs.Reference_Type := Self.Env.Reference (Key);
   begin
      --  Get rid of element
      for I in 1 .. V.Length loop
         if V.Get (I).El = Value then
            V.Remove_At (I);
            exit;
         end if;
      end loop;
   end Remove;

   package Referenced_Envs_Arrays is new Langkit_Support.Array_Utils
     (Referenced_Env, Positive, Referenced_Envs_Vectors.Elements_Array);

   ---------
   -- Get --
   ---------

   function Get
     (Self          : Lexical_Env;
      Key           : Symbol_Type;
      From          : Element_T := No_Element;
      Recursive     : Boolean := True) return Env_Element_Array
   is
      use Internal_Envs;
      use Env_Element_Arrays;

      use Referenced_Envs_Arrays;

      function Get_Ref_Env_Elements
        (Self : Referenced_Env) return Env_Element_Array;

      function Get_Own_Elements
        (Self : Lexical_Env) return Env_Element_Array;
      --  Return the elements for Key contained by the internal map contained
      --  in this env.

      function Get_Ref_Env_Elements
        (Self : Referenced_Env) return Env_Element_Array is
      begin

         --  If the referenced environment has an origin point, and the client
         --  passed an origin from the request, see if the environment is
         --  reachable.

         if Self.From_Node /= No_Element
           and then From /= No_Element
           and then not Can_Reach (Self.From_Node, From)
         then
            return Env_Element_Arrays.Empty_Array;
         end if;

         return Get (Self.Env, Key, From, Recursive => False);
      end Get_Ref_Env_Elements;

      ----------------------
      -- Get_Own_Elements --
      ----------------------

      function Get_Own_Elements
        (Self : Lexical_Env) return Env_Element_Array
      is
         C : Cursor := Internal_Envs.No_Element;
      begin
         if Self.Env /= null then
            C := Self.Env.Find (Key);
         end if;

         return
           (if Has_Element (C)
            then Decorate

            --  We want to reverse the returned array, so that last inserted
            --  results are returned first.

              (Reverse_Array
                 (Env_Element_Vectors.To_Array (Element (C))),
               Self.Default_MD,
               Self.Parents_Rebindings)

            else Env_Element_Arrays.Empty_Array);
      end Get_Own_Elements;

      function Get_Refd_Elements
      is new Referenced_Envs_Arrays.Flat_Map_Gen
        (Env_Element, Env_Element_Array, Get_Ref_Env_Elements);
      --  Return the concatenation of Get_Own_Elements for this env and every
      --  parent.

      function Can_Reach_F (El : Env_Element) return Boolean is
        (Can_Reach (El.El, From));

   begin
      if Self = null then
         return Env_Element_Arrays.Empty_Array;
      end if;

      declare
         Parent_Env : constant Lexical_Env := Get_Env (Self.Parent);
         Ret : constant Env_Element_Array :=
           Get_Own_Elements (Self)
           & (if Recursive
              then Get_Refd_Elements
                (Referenced_Envs_Vectors.To_Array (Self.Referenced_Envs))
              else Env_Element_Arrays.Empty_Array)
           & Get_Refd_Elements
           (Referenced_Envs_Vectors.To_Array (Self.Transitive_Referenced_Envs))
           & (if Recursive
              then Get (Parent_Env, Key)
              else Env_Element_Arrays.Empty_Array);
      begin
         --  Only filter if a non null value was given for the From parameter
         return (if From = No_Element then Ret
                 else Env_Element_Arrays.Filter (Ret, Can_Reach_F'Access));
      end;
   end Get;

   ---------
   -- Get --
   ---------

   function Get
     (Self : Lexical_Env;
      Key  : Symbol_Type;
      From : Element_T := No_Element;
      Recursive     : Boolean := True) return Element_Array is
   begin
      return Unwrap (Get (Self, Key, From, Recursive));
   end Get;

   -----------
   -- Group --
   -----------

   function Group (Envs : Lexical_Env_Array) return Lexical_Env is
      N : constant Lexical_Env :=
        new Lexical_Env_Type'
          (Parent                     => No_Env_Getter,
           Node                       => No_Element,
           Referenced_Envs            => <>,
           Transitive_Referenced_Envs => <>,
           Env                        => null,
           Default_MD                 => Empty_Metadata,
           Parents_Rebindings         => null,
           Ref_Count                  => 1);
   begin
      for Env of Envs loop
         Reference (N, Env, No_Element, True);
      end loop;
      return N;
   end Group;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Self : in out Lexical_Env) is
      procedure Free is
        new Ada.Unchecked_Deallocation (Lexical_Env_Type, Lexical_Env);
      Refd_Env : Lexical_Env;
   begin

      --  Do not free the internal map for ref-counted allocated environments
      --  as all maps are owned by analysis unit owned environments.

      if Self.Ref_Count = No_Refcount then
         for Elts of Self.Env.all loop
            Env_Element_Vectors.Destroy (Elts);
         end loop;
         Destroy (Self.Env);
      end if;

      --  Referenced_Envs on the other hand are always owned by Self

      for Ref_Env of Self.Referenced_Envs loop
         Refd_Env := Ref_Env.Env;
         Dec_Ref (Refd_Env);
      end loop;
      Referenced_Envs_Vectors.Destroy (Self.Referenced_Envs);

      for Ref_Env of Self.Transitive_Referenced_Envs loop
         Refd_Env := Ref_Env.Env;
         Dec_Ref (Refd_Env);
      end loop;
      Referenced_Envs_Vectors.Destroy (Self.Transitive_Referenced_Envs);

      Free (Self);
   end Destroy;

   -------------
   -- Inc_Ref --
   -------------

   procedure Inc_Ref (Self : Lexical_Env) is
   begin
      if Self.Ref_Count = No_Refcount then
         return;
      end if;

      Self.Ref_Count := Self.Ref_Count + 1;
   end Inc_Ref;

   -------------
   -- Dec_Ref --
   -------------

   procedure Dec_Ref (Self : in out Lexical_Env) is
   begin
      if Self = null or else Self.Ref_Count = No_Refcount then
         return;
      end if;

      Self.Ref_Count := Self.Ref_Count - 1;
      if Self.Ref_Count = 0 then
         Dec_Ref (Self.Parent);
         Destroy (Self);
      end if;
      Self := null;
   end Dec_Ref;

   ---------------
   -- Reference --
   ---------------

   procedure Reference
     (Self            : Lexical_Env;
      To_Reference    : Lexical_Env;
      Referenced_From : Element_T := No_Element;
      Transitive      : Boolean   := False)
   is
   begin
      if Transitive then
         Referenced_Envs_Vectors.Append
           (Self.Transitive_Referenced_Envs,
            Referenced_Env'(Referenced_From, To_Reference));
      else
         Referenced_Envs_Vectors.Append
           (Self.Referenced_Envs,
            Referenced_Env'(Referenced_From, To_Reference));
      end if;
      Inc_Ref (To_Reference);
   end Reference;

   -------------
   -- Get_Env --
   -------------

   function Get_Env (Self : Env_Getter) return Lexical_Env is
   begin
      if Self.Dynamic then
         return Self.Getter_Fn (Self.Getter_State);
      else
         return Self.Env;
      end if;
   end Get_Env;

   -------------
   -- Inc_Ref --
   -------------

   procedure Inc_Ref (Self : Env_Getter) is
   begin
      if not Self.Dynamic then
         Inc_Ref (Self.Env);
      end if;
   end Inc_Ref;

   -------------
   -- Dec_Ref --
   -------------

   procedure Dec_Ref (Self : in out Env_Getter) is
   begin
      if not Self.Dynamic then
         Dec_Ref (Self.Env);
      end if;
   end Dec_Ref;

   -----------------------
   -- Simple_Env_Getter --
   -----------------------

   function Simple_Env_Getter (E : Lexical_Env) return Env_Getter
   is
     (Env_Getter'(False, Env => E));

   --------------------
   -- Dyn_Env_Getter --
   --------------------

   function Dyn_Env_Getter
     (Fn : Getter_Fn_T; State : Getter_State_T) return Env_Getter
   is
   begin
      return Env_Getter'(True, State, Fn);
   end Dyn_Env_Getter;

   ------------
   -- Orphan --
   ------------

   function Orphan (Self : Lexical_Env) return Lexical_Env is
   begin
      for Env of Self.Referenced_Envs loop
         Inc_Ref (Env.Env);
      end loop;

      return new Lexical_Env_Type'
        (Parent                     => No_Env_Getter,
         Node                       => Self.Node,
         Referenced_Envs            => Self.Referenced_Envs.Copy,
         Transitive_Referenced_Envs => Self.Transitive_Referenced_Envs.Copy,
         Env                        => Self.Env,
         Default_MD                 => Self.Default_MD,
         Parents_Rebindings         => Self.Parents_Rebindings,
         Ref_Count                  => 1);
   end Orphan;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Self : in out Env_Rebindings) is
      procedure Unchecked_Free
      is new Ada.Unchecked_Deallocation (Env_Rebindings_Type, Env_Rebindings);
   begin
      if Self /= null then
         Self.Ref_Count := Self.Ref_Count - 1;
         if Self.Ref_Count = 0 then
            Unchecked_Free (Self);
         end if;
      end if;
   end Destroy;

   -------------
   -- Combine --
   -------------

   function Combine (L, R : Env_Rebindings) return Env_Rebindings is
   begin
      if L = null and then R = null then
         return null;
      elsif L = null or else L.Size = 0 then
         return R;
      elsif R = null or else R.Size = 0 then
         return L;
      end if;

      return Ret : Env_Rebindings do
         Ret := new Env_Rebindings_Type (L.Size + R.Size);

         for J in 1 .. L.Size loop
            Ret.Rebindings (J) := L.Rebindings (J);
         end loop;

         for J in 1 .. R.Size loop
            Ret.Rebindings (J + L.Size + 1) := R.Rebindings (J);
         end loop;
      end return;
   end Combine;

   -----------------
   -- Get_New_Env --
   -----------------

   function Get_New_Env
     (Self : Env_Rebindings; Old_Env : Env_Getter) return Env_Getter
   is
   begin
      for J in 1 .. Self.Size loop
         if Get_Env (Old_Env) = Get_Env (Self.Rebindings (J).Old_Env) then
            return Self.Rebindings (J).New_Env;
         end if;
      end loop;

      return No_Env_Getter;
   end Get_New_Env;

end Langkit_Support.Lexical_Env;
