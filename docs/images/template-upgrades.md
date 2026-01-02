# Template Upgrade Semantics

Terraform does not upgrade existing LXC containers when a new template is
published. Templates are a create-time seed only.

## Canonical upgrade strategies

1. Replace (taint or recreate)
   - Destroy/recreate the container so the new template is applied.
2. Blue/green cutover
   - Create a new container from the new template.
   - Cut over DNS or traffic deliberately.

## Explicitly forbidden

- In-place upgrades that assume a template change will propagate.
- Manual template edits on running containers.

## Operator guidance

- Plan template upgrades as a rebuild event.
- Ensure known_hosts rotation is performed for the new container.
- Treat old containers as disposable once the cutover is complete.
