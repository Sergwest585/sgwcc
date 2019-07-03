------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                        B I N D O . B U I L D E R S                       --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--             Copyright (C) 2019, Free Software Foundation, Inc.           --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT; see file COPYING3.  If not, go to --
-- http://www.gnu.org/licenses for a complete copy of the license.          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Binderr; use Binderr;
with Butil;   use Butil;
with Opt;     use Opt;
with Output;  use Output;
with Types;   use Types;

with Bindo.Units; use Bindo.Units;

with GNAT;                 use GNAT;
with GNAT.Dynamic_HTables; use GNAT.Dynamic_HTables;

package body Bindo.Builders is

   -------------------------------
   -- Invocation_Graph_Builders --
   -------------------------------

   package body Invocation_Graph_Builders is

      -----------------
      -- Global data --
      -----------------

      Inv_Graph : Invocation_Graph := Invocation_Graphs.Nil;
      Lib_Graph : Library_Graph    := Library_Graphs.Nil;

      -----------------------
      -- Local subprograms --
      -----------------------

      procedure Create_Edge (IR_Id : Invocation_Relation_Id);
      pragma Inline (Create_Edge);
      --  Create a new edge for invocation relation IR_Id in invocation graph
      --  Inv_Graph.

      procedure Create_Edges (U_Id : Unit_Id);
      pragma Inline (Create_Edges);
      --  Create new edges for all invocation relations of unit U_Id

      procedure Create_Vertex
        (IC_Id  : Invocation_Construct_Id;
         LGV_Id : Library_Graph_Vertex_Id);
      pragma Inline (Create_Vertex);
      --  Create a new vertex for invocation construct IC_Id in invocation
      --  graph Inv_Graph. The vertex is linked to vertex LGV_Id of library
      --  graph Lib_Graph.

      procedure Create_Vertices (U_Id : Unit_Id);
      pragma Inline (Create_Vertices);
      --  Create new vertices for all invocation constructs of unit U_Id in
      --  invocation graph Inv_Graph.

      ----------------------------
      -- Build_Invocation_Graph --
      ----------------------------

      function Build_Invocation_Graph
        (Lib_G : Library_Graph) return Invocation_Graph
      is
      begin
         pragma Assert (Present (Lib_G));

         --  Prepare the global data

         Inv_Graph :=
           Create (Initial_Vertices => Number_Of_Elaborable_Units,
                   Initial_Edges    => Number_Of_Elaborable_Units);
         Lib_Graph := Lib_G;

         For_Each_Elaborable_Unit (Create_Vertices'Access);
         For_Each_Elaborable_Unit (Create_Edges'Access);

         return Inv_Graph;
      end Build_Invocation_Graph;

      -----------------
      -- Create_Edge --
      -----------------

      procedure Create_Edge (IR_Id : Invocation_Relation_Id) is
         pragma Assert (Present (Inv_Graph));
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (IR_Id));

         IR_Rec : Invocation_Relation_Record renames
                    Invocation_Relations.Table (IR_Id);

         pragma Assert (Present (IR_Rec.Invoker));
         pragma Assert (Present (IR_Rec.Target));

         Invoker : Invocation_Graph_Vertex_Id;
         Target  : Invocation_Graph_Vertex_Id;

      begin
         --  Nothing to do when the target denotes an invocation construct that
         --  resides in a unit which will never be elaborated.

         if not Needs_Elaboration (IR_Rec.Target) then
            return;
         end if;

         Invoker := Corresponding_Vertex (Inv_Graph, IR_Rec.Invoker);
         Target  := Corresponding_Vertex (Inv_Graph, IR_Rec.Target);

         pragma Assert (Present (Invoker));
         pragma Assert (Present (Target));

         Add_Edge
           (G      => Inv_Graph,
            Source => Invoker,
            Target => Target,
            IR_Id  => IR_Id);
      end Create_Edge;

      ------------------
      -- Create_Edges --
      ------------------

      procedure Create_Edges (U_Id : Unit_Id) is
         pragma Assert (Present (Inv_Graph));
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));

         U_Rec : Unit_Record renames ALI.Units.Table (U_Id);

      begin
         for IR_Id in U_Rec.First_Invocation_Relation ..
                      U_Rec.Last_Invocation_Relation
         loop
            Create_Edge (IR_Id);
         end loop;
      end Create_Edges;

      -------------------
      -- Create_Vertex --
      -------------------

      procedure Create_Vertex
        (IC_Id  : Invocation_Construct_Id;
         LGV_Id : Library_Graph_Vertex_Id)
      is
         pragma Assert (Present (Inv_Graph));
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (IC_Id));
         pragma Assert (Present (LGV_Id));

         IC_Rec : Invocation_Construct_Record renames
                    Invocation_Constructs.Table (IC_Id);

         Body_LGV_Id : Library_Graph_Vertex_Id;

      begin
         --  Determine the proper library graph vertex which holds the body of
         --  the invocation construct.

         if IC_Rec.Placement = In_Body then
            Body_LGV_Id := Proper_Body (Lib_Graph, LGV_Id);
         else
            pragma Assert (IC_Rec.Placement = In_Spec);
            Body_LGV_Id := Proper_Spec (Lib_Graph, LGV_Id);
         end if;

         pragma Assert (Present (Body_LGV_Id));

         Add_Vertex
           (G      => Inv_Graph,
            IC_Id  => IC_Id,
            LGV_Id => Body_LGV_Id);
      end Create_Vertex;

      ---------------------
      -- Create_Vertices --
      ---------------------

      procedure Create_Vertices (U_Id : Unit_Id) is
         pragma Assert (Present (Inv_Graph));
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));

         U_Rec  : Unit_Record renames ALI.Units.Table (U_Id);
         LGV_Id : constant Library_Graph_Vertex_Id :=
                    Corresponding_Vertex (Lib_Graph, U_Id);

         pragma Assert (Present (LGV_Id));

      begin
         for IC_Id in U_Rec.First_Invocation_Construct ..
                      U_Rec.Last_Invocation_Construct
         loop
            Create_Vertex (IC_Id, LGV_Id);
         end loop;
      end Create_Vertices;
   end Invocation_Graph_Builders;

   ----------------------------
   -- Library_Graph_Builders --
   ----------------------------

   package body Library_Graph_Builders is

      ---------------------
      -- Data structures --
      ---------------------

      procedure Destroy_Line_Number (Line : in out Logical_Line_Number);
      pragma Inline (Destroy_Line_Number);
      --  Destroy line number Line

      function Hash_Unit (U_Id : Unit_Id) return Bucket_Range_Type;
      pragma Inline (Hash_Unit);
      --  Obtain the hash value of key U_Id

      package UL is new Dynamic_Hash_Tables
        (Key_Type              => Unit_Id,
         Value_Type            => Logical_Line_Number,
         No_Value              => No_Line_Number,
         Expansion_Threshold   => 1.5,
         Expansion_Factor      => 2,
         Compression_Threshold => 0.3,
         Compression_Factor    => 2,
         "="                   => "=",
         Destroy_Value         => Destroy_Line_Number,
         Hash                  => Hash_Unit);

      -----------------
      -- Global data --
      -----------------

      Lib_Graph : Library_Graph := Library_Graphs.Nil;

      Unit_To_Line : UL.Dynamic_Hash_Table := UL.Nil;
      --  The map of unit name -> line number, used to detect duplicate unit
      --  names and report errors.

      -----------------------
      -- Local subprograms --
      -----------------------

      procedure Add_Unit
        (U_Id : Unit_Id;
         Line : Logical_Line_Number);
      pragma Inline (Add_Unit);
      --  Create a relationship between unit U_Id and its declaration line in
      --  map Unit_To_Line.

      procedure Create_Forced_Edge
        (Pred : Unit_Id;
         Succ : Unit_Id);
      pragma Inline (Create_Forced_Edge);
      --  Create a new forced edge between predecessor unit Pred and successor
      --  unit Succ.

      procedure Create_Forced_Edges;
      pragma Inline (Create_Forced_Edges);
      --  Inspect the contents of the forced-elaboration-order file, and create
      --  specialized edges for each valid pair of units listed within.

      procedure Create_Spec_And_Body_Edge (U_Id : Unit_Id);
      pragma Inline (Create_Spec_And_Body_Edge);
      --  Establish a link between the spec and body of unit U_Id. In certain
      --  cases this may result in a new edge which is added to library graph
      --  Lib_Graph.

      procedure Create_Vertex (U_Id : Unit_Id);
      pragma Inline (Create_Vertex);
      --  Create a new vertex for unit U_Id in library graph Lib_Graph

      procedure Create_With_Edge
        (W_Id : With_Id;
         Succ : Library_Graph_Vertex_Id);
      pragma Inline (Create_With_Edge);
      --  Create a new edge for with W_Id where the predecessor is the library
      --  graph vertex of the withed unit, and the successor is Succ. The edge
      --  is added to library graph Lib_Graph.

      procedure Create_With_Edges (U_Id : Unit_Id);
      pragma Inline (Create_With_Edges);
      --  Establish links between unit U_Id and its predecessor units. The new
      --  edges are added to library graph Lib_Graph.

      procedure Create_With_Edges
        (U_Id : Unit_Id;
         Succ : Library_Graph_Vertex_Id);
      pragma Inline (Create_With_Edges);
      --  Create new edges for all withs of unit U_Id where the predecessor is
      --  some withed unit, and the successor is Succ. The edges are added to
      --  library graph Lib_Graph.

      procedure Duplicate_Unit_Error
        (U_Id : Unit_Id;
         Nam  : Unit_Name_Type;
         Line : Logical_Line_Number);
      pragma Inline (Duplicate_Unit_Error);
      --  Emit an error concerning the duplication of unit U_Id with name Nam
      --  that is redeclared in the forced-elaboration-order file at line Line.

      procedure Internal_Unit_Info (Nam : Unit_Name_Type);
      pragma Inline (Internal_Unit_Info);
      --  Emit an information message concerning the omission of an internal
      --  unit with name Nam from the creation of forced edges.

      function Is_Duplicate_Unit (U_Id : Unit_Id) return Boolean;
      pragma Inline (Is_Duplicate_Unit);
      --  Determine whether unit U_Id is already recorded in map Unit_To_Line

      function Is_Significant_With (W_Id : With_Id) return Boolean;
      pragma Inline (Is_Significant_With);
      --  Determine whether with W_Id plays a significant role in elaboration

      procedure Missing_Unit_Info (Nam : Unit_Name_Type);
      pragma Inline (Missing_Unit_Info);
      --  Emit an information message concerning the omission of an undefined
      --  unit found in the forced-elaboration-order file.

      --------------
      -- Add_Unit --
      --------------

      procedure Add_Unit
        (U_Id : Unit_Id;
         Line : Logical_Line_Number)
      is
      begin
         pragma Assert (Present (U_Id));

         UL.Put (Unit_To_Line, U_Id, Line);
      end Add_Unit;

      -------------------------
      -- Build_Library_Graph --
      -------------------------

      function Build_Library_Graph return Library_Graph is
      begin
         --  Prepare the global data

         Lib_Graph :=
           Create (Initial_Vertices => Number_Of_Elaborable_Units,
                   Initial_Edges    => Number_Of_Elaborable_Units);

         For_Each_Elaborable_Unit (Create_Vertex'Access);
         For_Each_Elaborable_Unit (Create_Spec_And_Body_Edge'Access);
         For_Each_Elaborable_Unit (Create_With_Edges'Access);

         Create_Forced_Edges;

         return Lib_Graph;
      end Build_Library_Graph;

      ------------------------
      -- Create_Forced_Edge --
      ------------------------

      procedure Create_Forced_Edge
        (Pred : Unit_Id;
         Succ : Unit_Id)
      is
         pragma Assert (Present (Pred));
         pragma Assert (Present (Succ));

         Pred_LGV_Id : constant Library_Graph_Vertex_Id :=
                         Corresponding_Vertex (Lib_Graph, Pred);
         Succ_LGV_Id : constant Library_Graph_Vertex_Id :=
                         Corresponding_Vertex (Lib_Graph, Succ);

         pragma Assert (Present (Pred_LGV_Id));
         pragma Assert (Present (Succ_LGV_Id));

      begin
         Write_Unit_Name (Name (Pred));
         Write_Str (" <-- ");
         Write_Unit_Name (Name (Succ));
         Write_Eol;

         Add_Edge
           (G    => Lib_Graph,
            Pred => Pred_LGV_Id,
            Succ => Succ_LGV_Id,
            Kind => Forced_Edge);
      end Create_Forced_Edge;

      -------------------------
      -- Create_Forced_Edges --
      -------------------------

      procedure Create_Forced_Edges is
         Curr_Unit : Unit_Id;
         Iter      : Forced_Units_Iterator;
         Prev_Unit : Unit_Id;
         Unit_Line : Logical_Line_Number;
         Unit_Name : Unit_Name_Type;

      begin
         Prev_Unit    := No_Unit_Id;
         Unit_To_Line := UL.Create (20);

         --  Inspect the contents of the forced-elaboration-order file supplied
         --  to the binder using switch -f, and diagnose each unit accordingly.

         Iter := Iterate_Forced_Units;
         while Has_Next (Iter) loop
            Next (Iter, Unit_Name, Unit_Line);
            pragma Assert (Present (Unit_Name));

            Curr_Unit := Corresponding_Unit (Unit_Name);

            if not Present (Curr_Unit) then
               Missing_Unit_Info (Unit_Name);

            elsif Is_Internal_Unit (Curr_Unit) then
               Internal_Unit_Info (Unit_Name);

            elsif Is_Duplicate_Unit (Curr_Unit) then
               Duplicate_Unit_Error (Curr_Unit, Unit_Name, Unit_Line);

            --  Otherwise the unit is a valid candidate for a vertex. Create a
            --  forced edge between each pair of units.

            else
               Add_Unit (Curr_Unit, Unit_Line);

               if Present (Prev_Unit) then
                  Create_Forced_Edge
                    (Pred => Prev_Unit,
                     Succ => Curr_Unit);
               end if;

               Prev_Unit := Curr_Unit;
            end if;
         end loop;

         UL.Destroy (Unit_To_Line);
      end Create_Forced_Edges;

      -------------------------------
      -- Create_Spec_And_Body_Edge --
      -------------------------------

      procedure Create_Spec_And_Body_Edge (U_Id : Unit_Id) is
         Aux_LGV_Id : Library_Graph_Vertex_Id;
         LGV_Id     : Library_Graph_Vertex_Id;

      begin
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));

         LGV_Id := Corresponding_Vertex (Lib_Graph, U_Id);
         pragma Assert (Present (LGV_Id));

         --  The unit denotes a body that completes a previous spec. Link the
         --  spec and body. Add an edge between the predecessor spec and the
         --  successor body.

         if Is_Body_With_Spec (Lib_Graph, LGV_Id) then
            Aux_LGV_Id :=
              Corresponding_Vertex (Lib_Graph, Corresponding_Spec (U_Id));
            pragma Assert (Present (Aux_LGV_Id));

            Set_Corresponding_Item (Lib_Graph, LGV_Id, Aux_LGV_Id);

            Add_Edge
              (G    => Lib_Graph,
               Pred => Aux_LGV_Id,
               Succ => LGV_Id,
               Kind => Spec_Before_Body_Edge);

         --  The unit denotes a spec with a completing body. Link the spec and
         --  body.

         elsif Is_Spec_With_Body (Lib_Graph, LGV_Id) then
            Aux_LGV_Id :=
              Corresponding_Vertex (Lib_Graph, Corresponding_Body (U_Id));
            pragma Assert (Present (Aux_LGV_Id));

            Set_Corresponding_Item (Lib_Graph, LGV_Id, Aux_LGV_Id);
         end if;
      end Create_Spec_And_Body_Edge;

      -------------------
      -- Create_Vertex --
      -------------------

      procedure Create_Vertex (U_Id : Unit_Id) is
      begin
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));

         Add_Vertex
           (G    => Lib_Graph,
            U_Id => U_Id);
      end Create_Vertex;

      ----------------------
      -- Create_With_Edge --
      ----------------------

      procedure Create_With_Edge
        (W_Id : With_Id;
         Succ : Library_Graph_Vertex_Id)
      is
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (W_Id));
         pragma Assert (Present (Succ));

         Withed_Rec  : With_Record renames Withs.Table (W_Id);
         Withed_U_Id : constant Unit_Id :=
                         Corresponding_Unit (Withed_Rec.Uname);

         pragma Assert (Present (Withed_U_Id));

         Aux_LGV_Id    : Library_Graph_Vertex_Id;
         Kind          : Library_Graph_Edge_Kind;
         Withed_LGV_Id : Library_Graph_Vertex_Id;

      begin
         --  Nothing to do when the withed unit does not need to be elaborated.
         --  This prevents spurious dependencies that can never be satisfied.

         if not Needs_Elaboration (Withed_U_Id) then
            return;
         end if;

         Withed_LGV_Id := Corresponding_Vertex (Lib_Graph, Withed_U_Id);
         pragma Assert (Present (Withed_LGV_Id));

         --  The with comes with pragma Elaborate

         if Withed_Rec.Elaborate then
            Kind := Elaborate_Edge;

            --  The withed unit is a spec with a completing body. Add an edge
            --  between the body of the withed predecessor and the withing
            --  successor.

            if Is_Spec_With_Body (Lib_Graph, Withed_LGV_Id) then
               Aux_LGV_Id :=
                 Corresponding_Vertex
                   (Lib_Graph, Corresponding_Body (Withed_U_Id));
               pragma Assert (Present (Aux_LGV_Id));

               Add_Edge
                 (G    => Lib_Graph,
                  Pred => Aux_LGV_Id,
                  Succ => Succ,
                  Kind => Kind);
            end if;

         --  The with comes with pragma Elaborate_All

         elsif Withed_Rec.Elaborate_All then
            Kind := Elaborate_All_Edge;

         --  Otherwise this is a regular with

         else
            Kind := With_Edge;
         end if;

         --  Add an edge between the withed predecessor unit and the withing
         --  successor.

         Add_Edge
           (G    => Lib_Graph,
            Pred => Withed_LGV_Id,
            Succ => Succ,
            Kind => Kind);
      end Create_With_Edge;

      -----------------------
      -- Create_With_Edges --
      -----------------------

      procedure Create_With_Edges (U_Id : Unit_Id) is
         LGV_Id : Library_Graph_Vertex_Id;

      begin
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));

         LGV_Id := Corresponding_Vertex (Lib_Graph, U_Id);
         pragma Assert (Present (LGV_Id));

         Create_With_Edges
           (U_Id => U_Id,
            Succ => LGV_Id);
      end Create_With_Edges;

      -----------------------
      -- Create_With_Edges --
      -----------------------

      procedure Create_With_Edges
        (U_Id : Unit_Id;
         Succ : Library_Graph_Vertex_Id)
      is
         pragma Assert (Present (Lib_Graph));
         pragma Assert (Present (U_Id));
         pragma Assert (Present (Succ));

         U_Rec : Unit_Record renames ALI.Units.Table (U_Id);

      begin
         for W_Id in U_Rec.First_With .. U_Rec.Last_With loop
            if Is_Significant_With (W_Id) then
               Create_With_Edge (W_Id, Succ);
            end if;
         end loop;
      end Create_With_Edges;

      ------------------
      -- Destroy_Unit --
      ------------------

      procedure Destroy_Line_Number (Line : in out Logical_Line_Number) is
         pragma Unreferenced (Line);
      begin
         null;
      end Destroy_Line_Number;

      --------------------------
      -- Duplicate_Unit_Error --
      --------------------------

      procedure Duplicate_Unit_Error
        (U_Id : Unit_Id;
         Nam  : Unit_Name_Type;
         Line : Logical_Line_Number)
      is
         pragma Assert (Present (U_Id));
         pragma Assert (Present (Nam));

         Prev_Line : constant Logical_Line_Number :=
                       UL.Get (Unit_To_Line, U_Id);

      begin
         Error_Msg_Nat_1  := Nat (Line);
         Error_Msg_Nat_2  := Nat (Prev_Line);
         Error_Msg_Unit_1 := Nam;

         Error_Msg
           (Force_Elab_Order_File.all
            & ":#: duplicate unit name $ from line #");
      end Duplicate_Unit_Error;

      ---------------
      -- Hash_Unit --
      ---------------

      function Hash_Unit (U_Id : Unit_Id) return Bucket_Range_Type is
      begin
         pragma Assert (Present (U_Id));

         return Bucket_Range_Type (U_Id);
      end Hash_Unit;

      ------------------------
      -- Internal_Unit_Info --
      ------------------------

      procedure Internal_Unit_Info (Nam : Unit_Name_Type) is
      begin
         pragma Assert (Present (Nam));

         Write_Line
           ("""" & Get_Name_String (Nam) & """: predefined unit ignored");
      end Internal_Unit_Info;

      -----------------------
      -- Is_Duplicate_Unit --
      -----------------------

      function Is_Duplicate_Unit (U_Id : Unit_Id) return Boolean is
      begin
         pragma Assert (Present (U_Id));

         return UL.Contains (Unit_To_Line, U_Id);
      end Is_Duplicate_Unit;

      -------------------------
      -- Is_Significant_With --
      -------------------------

      function Is_Significant_With (W_Id : With_Id) return Boolean is
         pragma Assert (Present (W_Id));

         Withed_Rec  : With_Record renames Withs.Table (W_Id);
         Withed_U_Id : constant Unit_Id :=
                         Corresponding_Unit (Withed_Rec.Uname);

      begin
         --  Nothing to do for a unit which does not exist any more

         if not Present (Withed_U_Id) then
            return False;

         --  Nothing to do for a limited with

         elsif Withed_Rec.Limited_With then
            return False;

         --  Nothing to do when the unit does not need to be elaborated

         elsif not Needs_Elaboration (Withed_U_Id) then
            return False;
         end if;

         return True;
      end Is_Significant_With;

      -----------------------
      -- Missing_Unit_Info --
      -----------------------

      procedure Missing_Unit_Info (Nam : Unit_Name_Type) is
      begin
         pragma Assert (Present (Nam));

         Write_Line
           ("""" & Get_Name_String (Nam) & """: not present; ignored");
      end Missing_Unit_Info;
   end Library_Graph_Builders;

end Bindo.Builders;
