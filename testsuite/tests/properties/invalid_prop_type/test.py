from langkit.compiled_types import (
    ASTNode, root_grammar_class, Field
)
from langkit.diagnostics import Diagnostics
from langkit.expressions import Property, Self
from langkit.parsers import Grammar, Row

from os import path
from utils import emit_and_print_errors


Diagnostics.set_lang_source_dir(path.abspath(__file__))


@root_grammar_class()
class FooNode(ASTNode):
    pass


class BarCode(FooNode):
    a = Field()
    prop_1 = Property(Self.a.prop_2)


class BarNode(FooNode):
    prop_2 = Property(Self.parent.cast(BarCode).prop_1)


def lang_def():
    foo_grammar = Grammar('main_rule')
    foo_grammar.add_rules(
        main_rule=Row('example', foo_grammar.rule_2) ^ BarCode,
        rule_2=Row('example') ^ BarNode,
    )
    return foo_grammar

emit_and_print_errors(lang_def)
print('')
print 'Done'
