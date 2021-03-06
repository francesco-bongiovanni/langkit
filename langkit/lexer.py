from __future__ import absolute_import

from collections import defaultdict
from itertools import count
import re

from langkit.compile_context import get_context
from langkit.diagnostics import check_source_language
from langkit.names import Name
from langkit.template_utils import common_renderer


class Matcher(object):
    """
    Base class for a matcher. A matcher specificies in which case a given
    input will trigger a match.
    """

    def max_match_length(self):
        """
        Return the maximum number of characters this pattern will accept, or
        raise ValueError if it is unknown.
        :rtype: int
        """
        raise NotImplementedError()

    def render(self):
        """
        Render method to be overloaded in subclasses.
        :rtype: str
        """
        raise NotImplementedError()


class Pattern(Matcher):
    """
    Matcher. This will match a regular expression like pattern. Since the
    lexer DSL uses Quex underneath, you can find more documentation about
    the recognized regular expression language here: `Quex pattern language
     <http://quex.sourceforge.net/doc/html/usage/patterns/context-free.html>`_.
    """

    def __init__(self, pattern):
        self.pattern = pattern

    def max_match_length(self):
        for c in self.pattern:
            if re.escape(c) != c and c not in ('.', '\''):
                raise ValueError(
                    'Cannot compute the maximum number of characters this'
                    ' pattern will accept: {}'.format(repr(self.pattern))
                )
        return len(self.pattern)

    def render(self):
        return self.pattern


class Action(object):
    """
    Base class for an action. An action specificies what to do with a given
    match.
    """

    def render(self, lexer):
        """
        Render method to be overloaded in subclasses.

        :param Lexer lexer: The instance of the lexer from which this render
          function has been called.
        :rtype: str
        """
        raise NotImplemented()


class TokenAction(Action):
    """
    Abstract Base class for an action that sends a token. Subclasses of
    TokenAction can *only* be used as the instantiation of a token kind, in the
    declaration of a LexerToken subclass, as in::

        class MyToken(LexerToken):
            Identifier = WithSymbol()
            Keyword = WithText()
    """
    # This counter is used to preserve the order of TokenAction instantiations,
    # which allows us to get the declaration order of token enum kinds.
    _counter = iter(count(0))

    def __init__(self, start_ignore_layout=False, end_ignore_layout=False):
        """
        Create a new token action. This is meant to be called on subclasses of
        TokenAction.

        :param bool start_ignore_layout: If True, the token associated with
            this token action will trigger the start of layout ignore, which
            means that indent, dedent, and newline tokens will not be emitted
            by the lexer.

        :param bool end_ignore_layout: If True, the token associated with this
            token action will trigger the end of layout ignorance.

        Note that layout ignore works in a nested fashion: If the lexer reads 3
        tokens that starts layout ignore, it will need to read 3 tokens that
        ends it so that it is taken into account again. The lexer won't handle
        proper pairing: This is up to the parser's implementer.
        """
        self._index = next(TokenAction._counter)

        self.name = None
        ":type: names.Name"

        self.lexer = None
        self.start_ignore_layout = start_ignore_layout
        self.end_ignore_layout = end_ignore_layout

    @property
    def value(self):
        return self._index

    def render(self, lexer):
        """
        Return Quex code to implement this token action.

        :param Lexer lexer: Corresponding lexer.
        :rtype: str
        """
        raise NotImplementedError()

    def __call__(self, *args, **kwargs):
        """
        Shortcut to create token parsers in the grammar.
        """
        from langkit.parsers import Tok
        return Tok(self, *args, **kwargs)


class WithText(TokenAction):
    """
    TokenAction. The associated token kind will have the lexed text associated
    to it. A new string will be allocated by the parser each time. Suited for
    literals (numbers, strings, etc..)::

        class MyToken(LexerToken):
            # String tokens will keep the associated text when lexed
            StringLiteral = WithText()
    """

    def render(self, lexer):
        return "=> {}(Lexeme);".format(lexer.quex_token_name(self.name.upper))


class WithTrivia(WithText):
    """
    TokenAction. The associated token kind will have the lexed text associated
    to it. A new string will be allocated by the parser each time. Suited for
    literals (numbers, strings, etc..)::

        class MyToken(LexerToken):
            # String tokens will keep the associated text when lexed
            StringLiteral = WithText()
    """
    pass


class WithSymbol(TokenAction):
    """
    TokenAction. When the associated token kind will be lexed, a token will be
    created with the text corresponding to the match, but as an internalized
    symbol, so that if you have two tokens with the same text, the text will be
    shared amongst both::

        class MyToken(LexerToken):
            # Identifiers will keep an internalized version of the text
            Identifier = WithSymbol()
    """

    def render(self, lexer):
        return "=> {}(Lexeme);".format(lexer.quex_token_name(self.name.upper))


class LexerToken(object):
    """
    Base class from which your token class must derive. Every member needs to
    be an instanciation of a subclass of TokenAction, specifiying what is done
    with the resulting token.
    """
    # Built-in termination token. Since it will always be the first token kind,
    # its value will always be zero.
    Termination = WithText()

    # Built-in token to represent a lexing failure
    LexingFailure = WithText()

    def __init__(self, track_indent=False):
        import inspect

        if track_indent:
            self.__class__.Indent = WithText()
            self.__class__.Dedent = WithText()
            self.__class__.Newline = WithText()

        self.fields = []
        for c in inspect.getmro(self.__class__):
            self.add_tokens(c)

    def add_tokens(self, klass):
        for fld_name, fld_value in klass.__dict__.items():
            if isinstance(fld_value, TokenAction):
                fld_value.name = Name.from_camel(fld_name)
                self.fields.append(fld_value)

    def __iter__(self):
        return (fld for fld in self.fields)

    def __len__(self):
        return len(self.fields)


class Patterns(object):
    """
    This is just a wrapper class, instantiated so that we can setattr patterns
    on it and the user can then type::

        mylexer.patterns.my_pattern

    To refer to a pattern.
    """
    pass


class Lexer(object):
    """
    This is the main lexer object, through which you will define your Lexer.
    At initialization time, you will need to provide an enum class to it, that
    will be used to identify the different kinds of tokens that your lexer can
    generate. This is a simple example for a simple calculator's lexer::

        from enum import Enum
        class TokenKind(Enum):
            Plus = 1
            Minus = 2
            Times = 3
            Div = 4
            Number = 5

        l = Lexer(TokenKind)

    You can add patterns to it, that are shortcuts to regex patterns, and that
    can refer to each others, like so::

        l.add_patterns(
            ('digit', r"[0-9]"),
            ('integer', r"({digit}(_?{digit})*)"),
        )

    Note that this is not necessary, just a convenient shortcut. After that
    you'll be able to define the match rules for your lexer, via the
    `add_rules` function::

        l.add_rules((
            (Literal("+"),       WithText(TokenKind.Plus))
            (Literal("-"),       WithText(TokenKind.Minus))
            (Literal("*"),       WithText(TokenKind.Times))
            (Literal("/"),       WithText(TokenKind.Div))
            (l.patterns.integer, WithText(TokenKind.Number))
        ))

    After that, your lexer is complete! You can use it in your parser to
    generate parse trees.
    """

    class PredefPattern(Pattern):
        """
        Class for a pattern defined in advance via the add_pattern method on
        the lexer.
        """

        def __init__(self, name, pattern):
            super(Lexer.PredefPattern, self).__init__(pattern)
            self.name = name

        def render(self):
            return "{{{}}}".format(self.name)

    def __init__(self, tokens_class, track_indent=False):
        """
        :param type tokens_class: The class for the lexer's tokens.
        :param bool track_indent: Whether to track indentation when lexing or
            not. If this is true, then the special Layout parsers can be used
            to do indentation sensitive parsing.
        """
        self.tokens = tokens_class(track_indent)
        assert isinstance(self.tokens, LexerToken)

        self.patterns = Patterns()
        self.__patterns = []
        self.rules = []
        self.tokens_set = {el.name for el in self.tokens}
        self.track_indent = track_indent

        # This map will keep a mapping from literal matches to token kind
        # values, so that you can find back those values if you have the
        # literal that corresponds to it.
        self.literals_map = {}

        self.prefix = None
        """
        Prefix to use for token names. Will be set to a meaningful value by
        the compile context.

        :type: str
        """

        # Map from token actions class names to set of token actions with that
        # class.
        self.token_actions = defaultdict(set)

        for el in self.tokens:
            self.token_actions[type(el).__name__].add(el)

        # These are automatic rules, useful for all lexers: handle end of input
        # and invalid tokens.
        self.add_rules(
            (Eof(),     self.tokens.Termination),
            (Failure(), self.tokens.LexingFailure),
        )

        if self.track_indent:
            self.add_rules(
                (Literal(r'\n'), self.tokens.Newline),
            )

    def add_patterns(self, *patterns):
        """
        Add the list of named patterns to the lexer's internal patterns. A
        named pattern is a pattern that you can refer to through the {}
        notation in another pattern, or directly via the lexer instance::

            l.add_patterns(
                ('digit', r"[0-9]"),
                ('integer', r"({digit}(_?{digit})*)"),
            )

            l.add_rules(
                (l.patterns.integer, WithText(TokenKind.Number))
                (Pattern("{integer}(\.{integer})?"),
                 WithText(TokenKind.Number))
            )

        Please note that the order of addition matters if you want to refer to
        patterns in other patterns.

        :param list[(str, str)] patterns: The list of patterns to add.
        """
        for k, v in patterns:
            predef_pattern = Lexer.PredefPattern(k, v)
            setattr(self.patterns, k.lower(), predef_pattern)
            self.__patterns.append(predef_pattern)

    def add_rules(self, *rules):
        """
        Add the list of rules to the lexer's internal list of rules. A rule is
        either:
          - A tuple of a Matcher and an Action to execute on this matcher. This
            is the common case;
          - An instance of a class derived from `MatcherAssoc`. This is used to
            implement custom matching behaviour, such as in the case of `Case`.

        Please note that the order of addition matters. It will determine which
        rules are tried first by the lexer, so you could in effect make some
        rules 'dead' if you are not careful.

        :param rules: The list of rules to add.
        :type rules: list[(Matcher, Action)|RuleAssoc]
        """

        for matcher_assoc in rules:
            if type(matcher_assoc) is tuple:
                assert len(matcher_assoc) == 2
                matcher, action = matcher_assoc
                rule_assoc = RuleAssoc(matcher, action)
            else:
                assert isinstance(matcher_assoc, RuleAssoc)
                rule_assoc = matcher_assoc

            self.rules.append(rule_assoc)

            m, a = self.rules[-1].matcher, self.rules[-1].action
            if isinstance(m, Literal):
                # Add a mapping from the literal representation of the token to
                # itself, so that we can find tokens via their literal
                # representation.
                self.literals_map[m.to_match] = a

    def emit(self):
        """
        Return the content of the .qx file corresponding to this lexer
        specification. This function is not to be called by the client, and
        will be called by langkit when needed.

        :rtype: str
        """
        return common_renderer.render(
            "lexer/quex_lexer_spec",
            tokens=self.tokens,
            patterns=self.__patterns,
            rules=self.rules,
            lexer=self
        )

    def token_base_name(self, token):
        """
        Helper function to get the name of a token.

        :param TokenAction|Enum|Name|str token: Input token. It can be either a
            TokenAction subclass (i.e. a Lexer subclass attribute), an enum
            value from "self.tokens", the token Name or a string (case
            insensitive token name).
        :rtype: Name
        """
        if isinstance(token, TokenAction):
            return token.name
        elif isinstance(token, Name):
            assert token in self.tokens_set
            return token
        else:
            assert isinstance(token, str), (
                "Bad type for {}, supposed to be str|{}".format(
                    token, self.tokens.__name__
                )
            )
            name = Name.from_lower(token.lower())
            if name in self.tokens_set:
                return name
            elif token in self.literals_map:
                return self.literals_map[token].name
            else:
                check_source_language(
                    False,
                    "{} token literal is not part of the valid tokens for "
                    "this grammar".format(token)
                )

    def quex_token_name(self, token):
        """
        Helper function to get the name of the C constant to represent the kind
        of "token".

        :param TokenAction|Enum|Name|str token: See the token_base_name method.
        :rtype: str
        """
        assert self.prefix is not None, (
            "Lexer's prefix needs to be set before emission"
        )
        return "{}{}".format(self.prefix, self.token_base_name(token).upper)

    def c_token_name(self, token):
        """
        Helper function to get the name of the Quex constant to represent the
        kind of "token".

        :param TokenAction|Enum|Name|str token: See the token_base_name method.
        :rtype: str
        """
        prefixed_name = get_context().lang_name + self.token_base_name(token)
        return prefixed_name.upper

    def ada_token_name(self, token):
        """
        Helper function to get the name of the Ada enumerator to represent the
        kind of "token".

        :param TokenAction|Enum|Name|str token: See the token_base_name method.
        :rtype: str
        """
        prefixed_name = get_context().lang_name + self.token_base_name(token)
        return prefixed_name.camel_with_underscores

    @property
    def sorted_tokens(self):
        """
        Return the list of token types sorted by their corresponding numeric
        values.

        :rtype: list[TokenAction]
        """
        return sorted(self.tokens, key=lambda t: t.value)

    def __getattr__(self, attr):
        """
        Shortcut to get a TokenAction stored in self.tokens.
        """
        return getattr(self.tokens, attr)


class Literal(Matcher):
    """
    Matcher. This matcher will match the string given in parameter,
    literally. This means that characters which would be special in a
    Pattern will be regular characters here::

        Pattern("a+")   # Matches one or more a
        Literal("a+")   # Matches "a" followed by "+"
    """
    def __init__(self, to_match):
        self.to_match = to_match

    def max_match_length(self):
        return len(self.to_match)

    def render(self):
        return '"{}"'.format(self.to_match)


class NoCase(Matcher):
    """
    Matcher. This is a shortcut for a case insensitive pattern, so that::

        Pattern(r"\C{abcd}")

    is equivalent to::

        NoCase("abcd")
    """

    def __init__(self, to_match):
        self.to_match = to_match

    def max_match_length(self):
        return Pattern(self.to_match).max_match_length()

    def render(self):
        return '\C{{{}}}'.format(self.to_match)


class Eof(Matcher):
    """
    Matcher. Matches the end of the file/input stream.
    """
    def __init__(self):
        pass

    def max_match_length(self):
        return 0

    def render(self):
        return "<<EOF>>"


class Failure(Matcher):
    """
    Matcher. Matches a case of failure in the lexer.
    """
    def __init__(self):
        pass

    def render(self):
        return "on_failure"


class Ignore(Action):
    """
    Action. Basically ignore the matched text.
    """
    def render(self, lexer):
        return "{ }"


class RuleAssoc(object):
    """
    Base class for a matcher -> action association. This class should not be
    used directly, since you can provide a tuple to add_rules, that will be
    expanded to a RuleAssoc.
    """
    def __init__(self, matcher, action):
        self.matcher = matcher
        self.action = action

    def render(self, lexer):
        return "{} {}".format(
            self.matcher.render(),
            self.action.render(lexer)
        )


class Alt(object):
    """
    Holder class used to specify the alternatives to a Case rule. Can only
    be used in this context.
    """
    def __init__(self, prev_token_cond=None, send=None, match_size=None):
        self.prev_token_cond = prev_token_cond
        self.send = send
        self.match_size = match_size


class Case(RuleAssoc):
    """
    Special rule association that enables dispatching the action depending
    on the previously parsed token. The canonical example is the one for
    which this class was added: in the Ada language, a tick character can be
    used either as the start of a character literal, or as an attribute
    expression.

    One way to disambiguate is by looking at the previous token. An
    attribute expression can only happen is the token to the left is an
    identifier or the "all" keyword. In the rest of the cases, a tick will
    correspond to a character literal, or be a lexing error.

    We can express that with the case rule this way::

        Case(Pattern("'.'"),
             Alt(prev_token_cond=(Token.Identifier, Token.All),
                 send=Token.Tick,
                 match_size=1),
             Alt(send=Token.Char, match_size=3)),

    If the previous token is an Identifier or an All, then we send
    Token.Tick, with a match size of 1. We need to specify that because if
    the lexer arrived here, it matched one tick, any char, and another tick,
    so it needs to rewind back to the first tick.

    Else, then we matched a regular character literal. We send it.
    """

    class CaseAction(Action):
        def __init__(self, max_match_len, *alts):
            super(Case.CaseAction, self).__init__()
            self.max_match_len = max_match_len

            for i, alt in enumerate(alts):
                assert isinstance(alt, Alt), (
                    'Invalid alternative to Case matcher: {}'.format(alt)
                )
                assert alt.match_size <= max_match_len, (
                    'Match size for this Case alternative ({}) cannot be'
                    ' longer than the Case matcher ({} chars)'.format(
                        alt.match_size, max_match_len
                    )
                )

            assert alts[-1].prev_token_cond is None, (
                "The last alternative to a case matcher "
                "must have no prev token condition"
            )

            self.alts = alts[:-1]
            self.last_alt = alts[-1]

        def render(self, lexer):
            return common_renderer.render(
                "lexer/case_action",
                alts=self.alts,
                last_alt=self.last_alt,
                max_match_len=self.max_match_len,
                lexer=lexer
            )

    def __init__(self, matcher, *alts):
        super(Case, self).__init__(
            matcher, Case.CaseAction(matcher.max_match_length(), *alts)
        )
