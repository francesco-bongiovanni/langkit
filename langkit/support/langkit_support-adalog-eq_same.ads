with Langkit_Support.Adalog.Abstract_Relation;
use Langkit_Support.Adalog.Abstract_Relation;
with Langkit_Support.Adalog.Logic_Ref;
with Langkit_Support.Adalog.Unify;
with Langkit_Support.Adalog.Unify_LR;

--  Convenience wrapper generic package that, from a type implementing
--  equality, will instantiate all the needed stuff to create logical
--  equations containing that type, namely:
--
--  * A Logic_Ref instantiation so that you can have logical variables holding
--  values of the type.
--
--  * An instantiation of Unify, so that you can do logical equality comparison
--  between logic references and real instances of the type.

generic
   type LR_Type is private;
   with function Element_Image (E : LR_Type) return String is <>;
package Langkit_Support.Adalog.Eq_Same is

   package Refs is new Logic_Ref (LR_Type, Element_Image);

   type Dummy_Convert_Data is null record;
   No_Data : constant Dummy_Convert_Data := (null record);

   function Convert
     (C_Data : Dummy_Convert_Data; From : LR_Type) return LR_Type
   is (From) with Inline;

   function Equals (L, R : LR_Type) return Boolean is (L = R);

   package Refcounted_Impl is new Unify
     (LR_Type, LR_Type,
      Dummy_Convert_Data, Dummy_Convert_Data, No_Data, No_Data,
      Left_Var  => Refs.Refcounted_Logic_Var,
      Right_Var => Refs.Refcounted_Logic_Var);

   package Raw_Impl is new Unify
     (LR_Type, LR_Type,
      Dummy_Convert_Data, Dummy_Convert_Data, No_Data, No_Data,
      Left_Var  => Refs.Raw_Logic_Var,
      Right_Var => Refs.Raw_Logic_Var);

   subtype Refcounted_Member_Array is Refcounted_Impl.Unify_Left.R_Type_Array;
   subtype Raw_Member_Array is Raw_Impl.Unify_Left.R_Type_Array;

   --  This package can be used to provide custom bind operations, with a
   --  custom conversion from LR_Type to LR_Type.

   generic
      type Converter is private;
      No_Data : Converter;

      with function Convert (Data : Converter; From : LR_Type) return LR_Type;
      with function Equals (L, R : LR_Type) return Boolean is <>;
   package Raw_Custom_Bind is

      package Impl is new Unify
        (LR_Type, LR_Type,
         Converter, Converter, No_Data, No_Data,
         Convert, Convert, Equals, Equals,
         Refs.Raw_Logic_Var, Refs.Raw_Logic_Var);

      function Create (L, R : Refs.Raw_Logic_Var.Var; Data : Converter)
        return Relation
      is
        (Relation (Impl.Equals (L, R, Data, Data)));

      function Create (L    : Refs.Raw_Logic_Var.Var;
                       R    : LR_Type;
                       Data : Converter)
                             return Relation
      is
        (Relation (Impl.Equals (L, R, Data)));

      function Create (L    : LR_Type;
                       R    : Refs.Raw_Logic_Var.Var;
                       Data : Converter)
                             return Relation
      is
        (Relation (Impl.Equals (L, R, Data)));

   end Raw_Custom_Bind;

   generic
      type Converter is private;
      with function Convert (Data : Converter; From : LR_Type) return LR_Type;
   package Refcounted_Custom_Bind is
      package Impl is new Unify_LR
        (LR_Type, LR_Type,
         Converter, Converter,
         Convert, Convert,
         Refs.Refcounted_Logic_Var, Refs.Refcounted_Logic_Var);
   end Refcounted_Custom_Bind;

end Langkit_Support.Adalog.Eq_Same;
