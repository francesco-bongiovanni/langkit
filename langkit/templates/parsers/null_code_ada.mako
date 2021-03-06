## vim: filetype=makoada

% if parser.get_type().is_list_type:
   ${res} :=
    (${parser.get_type().storage_type_name()}_Alloc.Alloc (Parser.Mem_Pool));
   ${res}.Unit := Parser.Unit;

   ${res}.Token_Start := Token_Index'Max (1, ${pos_name} - 1);
   ${res}.Token_End := No_Token_Index;

% else:
   ${res} := ${parser.get_type().storage_nullexpr()};
% endif
