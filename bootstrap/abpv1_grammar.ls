
export
  S:
    func: 'plus', params:
      * func: 'alternative', params:
          * * func: 'void', params: [ func: 'terminal', params: ['\n'] ]
            * func: 'nonterminal', params: ['Rule']
          ...
      ...
  Rule:
    func: 'sequence', params:
      * * func: 'nonterminal', params: ['NT']
        * func: 'void', params: [ func: 'terminal', params: [' '] ]
        * func: 'alternative', params:
            * * func: 'terminal', params: ['←']
              * func: 'terminal', params: ['↖']
            ...
        * func: 'void', params: [ func: 'terminal', params: [' '] ]
        * func: 'nonterminal', params: ['Big']
      ...
  Big:
    flags: {pruned: true}
    func: 'alternative', params:
      * * func: 'nonterminal', params: ['ALT']
        * func: 'nonterminal', params: ['SEQ']
        * func: 'nonterminal', params: ['Medium']
      ...
  Medium:
    flags: {pruned: true}
    func: 'alternative', params:
      * * func: 'nonterminal', params: ['VOID']
        * func: 'nonterminal', params: ['STAR']
        * func: 'nonterminal', params: ['PLUS']
        * func: 'nonterminal', params: ['Small']
      ...
  Small:
    flags: {pruned: true}
    func: 'alternative', params:
      * * func: 'nonterminal', params: ['T']
        * func: 'nonterminal', params: ['NT']
        * func: 'sequence', params:
            * * func: 'void', params: [ func: 'terminal', params: ['('] ]
              * func: 'nonterminal', params: ['Big']
              * func: 'void', params: [ func: 'terminal', params: [')'] ]
            ...
      ...
  ALT:
    func: 'sequence', params:
      * * func: 'alternative', params:
            * * func: 'nonterminal', params: ['SEQ']
              * func: 'nonterminal', params: ['Medium']
            ...
        * func: 'plus', params:
            * func: 'sequence', params:
                * * func: 'void', params: [ func: 'terminal', params: [' | '] ]
                  * func: 'alternative', params:
                      * * func: 'nonterminal', params: ['SEQ']
                        * func: 'nonterminal', params: ['Medium']
                      ...
                ...
            ...
      ...
  SEQ:
    func: 'sequence', params:
      * * func: 'nonterminal', params: ['Medium']
        * func: 'plus', params:
            * func: 'sequence', params:
                * * func: 'void', params: [ func: 'terminal', params: [' '] ]
                  * func: 'nonterminal', params: ['Medium']
                ...
            ...
      ...
  VOID:
    func: 'sequence', params:
      * * func: 'void', params: [ func: 'terminal', params: [':'] ]
        * func: 'nonterminal', params: ['Small']
      ...
  STAR:
    func: 'sequence', params:
      * * func: 'nonterminal', params: ['Small']
        * func: 'void', params: [ func: 'terminal', params: ['*'] ]
      ...
  PLUS:
    func: 'sequence', params:
      * * func: 'nonterminal', params: ['Small']
        * func: 'void', params: [ func: 'terminal', params: ['+'] ]
      ...
  NT:
    func: 'sequence', params:
      * * func: 'terminal', params: [['AZ']]
        * func: 'star', params: [ func: 'terminal', params: [['az', 'AZ']] ]
      ...
  T:
    func: 'alternative', params:
      * * func: 'sequence', params:
            * * func: 'terminal', params: ['\'']
              * func: 'star', params:
                  * func: 'alternative', params:
                      * * func: 'terminal', params: ['\\\'']
                        * func: 'terminal', params: [['^','\'\'']]
                      ...
                  ...
              * func: 'terminal', params: ['\'']
            ...
        * func: 'sequence', params:
            * * func: 'terminal', params: ['[']
              * func: 'star', params:
                  * func: 'alternative', params:
                      * * func: 'terminal', params: ['\\]']
                        * func: 'terminal', params: [['^',']]']]
                      ...
                  ...
              * func: 'terminal', params: [']']
            ...
      ...
