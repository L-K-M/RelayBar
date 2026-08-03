# RelayBar Interface Principles

These principles govern new or changed application UI. They are design
constraints, not claims about implemented behavior; system specs remain the
authority for shipped behavior, and active task specs define proposed work.

## 1. The bar is for tunnels

The menu-bar icon and tunnel list communicate connection state and primary
tunnel actions only. Product identity, release controls, and persistent app
maintenance status stay in Settings; they do not create list state.

**Operational test:** A screenshot of the list must not change because an app
update is available, a background check failed, or About information changed.

## 2. Consent licenses the interruption

A window, alert, browser launch, or other interruption must trace to a direct
action in the current session or an explicit standing preference whose copy
describes that behavior. Standing consent never permits RelayBar to stop an
active tunnel without disclosing the effect at the decision point.

**Operational test:** For every interrupting surface, identify the action or
preference that authorized it. If it can end a connection, the same final
choice must name the number of affected tunnels and offer a safe way to defer.

## 3. Truth from the bundle, promises from the network

Unconditionally visible product facts come from the running bundle or local
system state. Network-derived claims appear only after the request that
justifies them, use bounded transient state, and are not presented as durable
offline truth.

**Operational test:** Disconnect the network and reopen the popover. Every
visible statement remains true, and no cached **Up to date** claim survives
from an earlier session.

## 4. Calm at default, graceful under pressure

At the default system text size, development locale, and normal state, each
popover screen fits the 380 × 440 point content budget without unnecessary
scrolling. Larger text, longer localization, focus chrome, and error captions
may require scrolling but must never cause clipping, overlap, or horizontal
movement.

**Operational test:** Verify the default layout without a scrollbar, then
repeat with larger text, the longest caption, keyboard focus, and a visible
vertical scrollbar; every control stays reachable and the content remains
horizontally stable.
