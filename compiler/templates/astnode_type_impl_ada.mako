## vim: filetype=makoada

   --
   --  Primitives for ${cls.name()}
   --

% if not cls.abstract:
   ----------
   -- Kind --
   ----------

   overriding
   function Kind (Node : access ${cls.name()}_Type) return AST_Node_Kind is
   begin
      return ${cls.name()}_Kind;
   end Kind;

   ---------------
   -- Kind_Name --
   ---------------

   overriding
   function Kind_Name (Node : access ${cls.name()}_Type) return String is
   begin
      return "${cls.repr_name()}";
   end Kind_Name;

   -----------
   -- Image --
   -----------

   overriding
   function Image (Node : access ${cls.name()}_Type) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Kind_Name (Node));
      Append (Result, '[');
      Append (Result, Image (Sloc_Range (AST_Node (Node))));
      Append (Result, "](");

      % for i, (t, f) in enumerate(d for d in all_field_decls if d[1].repr):
          % if i > 0:
              Append (Result, ", ");
          % endif

          % if t.is_ptr:
              if Node.F_${f.name} /= null then
          % endif

          % if is_ast_node(t):
             Append (Result, Image (AST_Node (Node.F_${f.name})));
          % else:
             Append (Result, Image (Node.F_${f.name}));
          % endif

          % if t.is_ptr:
              else
                 Append (Result, "None");
              end if;
          % endif
      % endfor

      Append (Result, ')');
      return To_String (Result);
   end Image;

   -----------------
   -- Child_Count --
   -----------------

   overriding
   function Child_Count (Node : access ${cls.name()}_Type) return Natural is
   begin
      return ${len(astnode_field_decls)};
   end Child_Count;

   ---------------
   -- Get_Child --
   ---------------

   overriding
   procedure Get_Child (Node  : access ${cls.name()}_Type;
                        Index : Natural;
                        Exists : out Boolean;
                        Result : out AST_Node) is
      ## Some ASTnodes have no ASTNode child: avoid the "unused parameter"
      ## compilation warning for them.
      % if not astnode_field_decls:
          pragma Unreferenced (Node);
          pragma Unreferenced (Result);
      % endif
   begin
      case Index is
          % for i, field in enumerate(astnode_field_decls):
              when ${i} =>
                  Result := AST_Node (Node.F_${field.name});
                  Exists := True;
          % endfor
          when others =>
             Exists := False;
             Result := null;
      end case;
   end Get_Child;

   --------------------------
   -- Compute_Indent_Level --
   --------------------------

   overriding
   procedure Compute_Indent_Level (Node : access ${cls.name()}_Type) is
   begin
      % if not any(is_ast_node(field_type) for field_type, _ in all_field_decls):
         null;
      % endif
      % for i, (field_type, field) in enumerate(all_field_decls):
         % if is_ast_node(field_type):
            if Node.F_${field.name} /= null then
               % if field.indent.kind == field.indent.KIND_REL_POS:
                  Node.F_${field.name}.Indent_Level :=
                     Node.Indent_Level + ${field.indent.rel_pos};
               % elif field.indent.kind == field.indent.KIND_TOKEN_POS:
                  Node.F_${field.name}.Indent_Level :=
                    Node.F_${field.indent.token_field_name}.Sloc_Range.End_Column - 1;
               % endif

               Compute_Indent_Level (Node.F_${field.name});
            end if;
         % endif
      % endfor
   end Compute_Indent_Level;

   -----------
   -- Print --
   -----------

   overriding
   procedure Print (Node  : access ${cls.name()}_Type;
                    Level : Natural := 0)
   is

      procedure Print_Indent (Level : Natural) is
      begin
         for I in 1 .. Level loop
            Put ("| ");
         end loop;
      end Print_Indent;

      Nod : constant AST_Node := AST_Node (Node);

   begin
      Print_Indent (Level);
      Put_Line (Kind_Name (Nod) & "[" & Image (Sloc_Range (Nod)) & "]");

      % for i, (t, f) in enumerate(d for d in all_field_decls if d[1].repr):
         % if t.is_ptr:
            if Node.F_${f.name} /= null
               and then not Is_Empty_List (Node.F_${f.name})
            then
               Print_Indent (Level + 1);
               Put_Line ("${f.name.lower}:");
               Node.F_${f.name}.Print (Level + 2);
            end if;
         % else:
            Print_Indent (Level + 1);
            Put_Line ("${f.name.lower}: " & Image (Node.F_${f.name}));
         % endif
      % endfor
   end Print;

   --------------
   -- Validate --
   --------------

   overriding
   procedure Validate (Node   : access ${cls.name()}_Type;
                       Parent : AST_Node := null)
   is
      Nod : constant AST_Node := AST_Node (Node);
   begin
      if Node.Parent /= Parent then
         raise Program_Error;
      end if;

      % for t, f in all_field_decls:
         % if is_ast_node (t):
            if Node.F_${f.name} /= null then
               Node.F_${f.name}.Validate (AST_Node (Node));
            end if;
         % endif
      % endfor
   end Validate;

   ---------------------
   -- Lookup_Children --
   ---------------------

   overriding
   function Lookup_Children (Node : access ${cls.name()}_Type;
                             Sloc : Source_Location;
                             Snap : Boolean := False) return AST_Node is
      ## For this implementation helper (i.e. internal primitive), we can
      ## assume that all lookups fall into this node's sloc range.

      Nod : constant AST_Node := AST_Node (Node);
      pragma Assert(Compare (Sloc_Range (Nod, Snap), Sloc) = Inside);

      Child : AST_Node;
      Pos   : Relative_Position;
      ## Some ASTnodes have no ASTNode child: avoid the "unused parameter"
      ## compilation warning for them.
      % if not astnode_field_decls:
          pragma Unreferenced (Child);
          pragma Unreferenced (Pos);
      % endif

   begin
      ## Look for a child node that contains Sloc (i.e. return the most
      ## precise result).

      % for i, (field_type, field) in enumerate(all_field_decls):
         % if is_ast_node(field_type):

            ## Note that we assume here that child nodes are ordered so
            ## that the first one has a sloc range that is before the
            ## sloc range of the second child node, etc.

            if Node.F_${field.name} /= null then
               Lookup_Relative (AST_Node (Node.F_${field.name}), Sloc,
                                Pos, Child,
                                Snap);
               case Pos is
                  when Before =>
                      ## If this is the first node, Sloc is before it, so
                      ## we can stop here.  Otherwise, Sloc is between the
                      ## previous child node and the next one...  so we can
                      ## stop here, too.
                      return Nod;

                  when Inside =>
                      return Child;

                  when After =>
                      ## Sloc is after the current child node, so see with
                      ## the next one.
                      null;
               end case;
            end if;
         % endif
      % endfor

      ## If we reach this point, we found no children that covers Sloc,
      ## but Node still covers it (see the assertion).

      return Nod;
   end Lookup_Children;

% endif

   ----------
   -- Free --
   ----------

   overriding
   procedure Free (Node : access ${cls.name()}_Type) is
   begin
      % for t, f in cls_field_decls:
         % if t.is_ptr:
            if Node.F_${f.name} /= null then
               Dec_Ref (AST_Node (Node.F_${f.name}));
            end if;
         % endif
      % endfor

      --  Let the base class destructor take care of inheritted fields

      Free (${base_name}_Access (Node));
   end Free;

   procedure Inc_Ref (Node : in out ${cls.name()}) is
   begin
      Inc_Ref (AST_Node (Node));
   end Inc_Ref;

   procedure Dec_Ref (Node : in out ${cls.name()}) is
   begin
      Dec_Ref (AST_Node (Node));
   end Dec_Ref;