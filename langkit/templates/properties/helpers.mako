## vim: filetype=makoada

<%def name="argument_list(property, dispatching)">
  (${property.self_arg_name} :
   access ${Self.type.value_type_name()}${"" if dispatching else "'Class"}

   % for arg in property.arguments:
      ; ${arg.name} : ${arg.type.name()}
      % if arg.default_value:
         := ${arg.default_value}
      % endif
   % endfor
  )
</%def>

<%def name="generate_logic_converter(conv_prop)">
   <%
   type_name = "Logic_Converter_{}".format(conv_prop.uid)
   root_class = T.root_node.name()
   sem_n = T.sem_node.name()
   %>

   ## We generate a custom type which is a functor in the C++ term, eg just a
   ## function with state. The state it needs to keep is the lexical env at the
   ## site where the logic binder is generated.
   type ${type_name} is record
      Env  : Lexical_Env;
   end record;

   No_${type_name} : constant ${type_name} := (Env => null);

   function Convert
     (Self : ${type_name}; From : ${sem_n}) return ${sem_n}
   with Inline;

   function Convert
     (Self : ${type_name}; From : ${sem_n})
      return ${sem_n}
   is
      % if not conv_prop.has_implicit_env:
         pragma Unreferenced (Self);
      % endif

   begin
      return ${sem_n}'
        (El => ${root_class} (${conv_prop.name}
          (${conv_prop.struct.name()} (From.El)
           % if conv_prop.has_implicit_env:
              , Self.Env
           % endif
         )),
         ## We don't propagate metadata for the moment in conversion, because
         ## attributes of the original entity don't necessarily propagate to the
         ## new entity.
         ## TODO: It will be necessary to allow the user to pass along
         ## metadata, all or some, at some point. Not clear yet how this should
         ## work, so keeping that for later.
         MD => No_Metadata,
         Is_Null => From.Is_Null,
         Parents_Bindings => From.Parents_Bindings
         );
   end Convert;
</%def>

<%def name="generate_logic_equal(eq_prop)">
   <% struct = eq_prop.struct.name() %>
   function Eq_${eq_prop.uid} (L, R : ${T.sem_node.name()}) return Boolean
   is
     (if L.El.all in ${struct}_Type'Class
      and then R.El.all in ${struct}_Type'Class
      then ${eq_prop.name} (${struct} (L.El), ${struct} (R.El))
      ## TODO: We probably still want to check some property of equality for
      ## the metadata.
      else raise Constraint_Error
           with "Wrong type for Eq_${eq_prop.uid} arguments");
</%def>

<%def name="generate_logic_binder(conv_prop, eq_prop)">
   <%
   cprop_uid = conv_prop.uid if conv_prop else "Default"
   eprop_uid = eq_prop.uid if eq_prop else "Default"
   package_name = "Bind_{}_{}".format(cprop_uid, eprop_uid)
   converter_type_name = "Logic_Converter_{}".format(cprop_uid)
   %>
   ## This package contains the necessary Adalog instantiations, so that we can
   ## create an equation that will bind two logic variables A and B so that::
   ##    B = PropertyCall (A.Value)
   ##
   ## Which is expressed as Bind (A, B, Property) in the DSL.
   package ${package_name} is new Eq_Node.Raw_Custom_Bind
     (${converter_type_name}, No_${converter_type_name},
      Convert, Eq_${eprop_uid});
</%def>

<%def name="generate_logic_predicates(prop)">
   % for (args_types, pred_id) in prop.logic_predicates:

   <%
      type_name = "{}_Predicate_Caller".format(pred_id)
      package_name = "{}_Pred".format(pred_id)
      root_class = T.root_node.name()
      formal_node_types = prop.get_concrete_node_types(args_types)
   %>

   type ${type_name} is record
      % for i, arg_type in enumerate(args_types):
      Field_${i} : ${arg_type.name()};
      % endfor
      Env        : Lexical_Env;
      Dbg_Img    : String_Access := null;
   end record;

   function Call
     (Self           : ${type_name}
     % for i in range(len(formal_node_types)):
     ; Node_${i} : ${T.sem_node.name()}
     % endfor
     ) return Boolean
   is
      % if not args_types and not prop.has_implicit_env:
         pragma Unreferenced (Self);
      % endif
   begin
      <%
         args = [
            '{} (Node_{}.El)'.format(formal_type.name(), i)
            for i, formal_type in enumerate(formal_node_types)
         ] + [
            'Self.Field_{}'.format(i)
            for i, _ in enumerate(args_types)
         ] + (
            ['Self.Env'] if prop.has_implicit_env else []
         )

         args_fmt = '({})'.format(', '.join(args)) if args else ''
      %>
      return ${prop.name} ${args_fmt};
   end Call;

   function Image (Self : ${type_name}) return String
   is (if Self.Dbg_Img /= null then Self.Dbg_Img.all else "");

   procedure Free (Self : in out ${type_name}) is
      procedure Free is new Ada.Unchecked_Deallocation (String, String_Access);
   begin
      Free (Self.Dbg_Img);
   end Free;

   package ${package_name} is
   new Predicate_${len(formal_node_types)}
     (${T.sem_node.name()}, Eq_Node.Refs.Raw_Logic_Var,
      ${type_name}, Free => Free);

   % endfor
</%def>

<%def name="inc_ref(var)">
   % if var.type.is_refcounted():
      Inc_Ref (${var.name});
   % endif
</%def>
