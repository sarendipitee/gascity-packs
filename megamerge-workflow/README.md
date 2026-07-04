# megamerge-workflow Pack

Workflow support for the Gas City megamerger agent's megamerge repairs.

This pack teaches agents how to use Jujutsu's simultaneous-edits pattern for
multi-line repair work:

- create a multi-parent integration merge
- include every stack head that must compile or behave together
- prove each intended stack head is actually in the merge ancestry
- create an empty scratch child above it
- make fixes in the scratch child
- route hunks back into their owning lines with `jj absorb`, `jj squash`, or
  `jj-hunk`
- keep the merge as the validation surface

Membership checks are explicit. A stack drawn near the megamerge is not enough:

```bash
jj log --no-pager -r '<stack-head> & ::<megamerge>'
jj log --no-pager -r '<megamerge>-'
```

If the first command does not print the stack head, restage the megamerge with
that head included before repairing or validating.

## Checks

```bash
gc lint megamerge-workflow
```
