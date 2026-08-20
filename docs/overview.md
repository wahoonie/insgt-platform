# InsightPhotos — Overview

## What We Do

InsightPhotos is a real estate photography company in California. We provide comprehensive media services for property listings: interior and exterior photography, aerial photography, video walkthroughs, 3D Matterport scans, Zillow 3D virtual tours, floor plans, and print-ready flyers.

Our core promise is **"Shoot Today. Live Tomorrow."** All media from a shoot is processed and delivered to the client by the next day. Same-day delivery is available as an upsell for agents who need it urgently.

## Who Uses the System

### Real Estate Agents (Primary)

Agents are our core customer. They need professional media to market their listings. The critical thing to understand about agents is that they are extremely busy, not technical, and have zero patience for friction. They don't want to learn a system. They want to place an order, get their photos, and move on.

They find us through referrals, internet searches, and industry events. We also do paparazzi-style photography and free headshots at real estate events to build relationships and visibility.

Common pain points: editing requests ("I want this brighter"), specific photo expectations ("I wanted a shot of the backyard from this angle and you didn't take it"), and anything that requires them to understand technical distinctions or navigate complex UI.

### Property Management / Rental Clients

Identical workflow to agents but with simpler needs. They need photos fast and don't care about AB 723 compliance, virtual tours, or print flyers. Speed is the only thing that matters.

### Legacy Clients

Clients who used us before AB 723 took effect on January 1, 2026. Their existing shoots may have unknown compliance states for listings that could still be active. The system must handle these gracefully — we can't retroactively determine which historical photos had material alterations applied.

## The Order Lifecycle

### 1. Order Placement
The agent places an order via the client app, text message, or email. They specify the property, the services they need, and their preferred time frame.

### 2. Scheduling
A single point person at InsightPhotos acts as the scheduler. They ensure the order information is entered correctly (if not already placed online), set the exact appointment time, and assign photographer(s). Multiple photographers may be assigned for different services — one for interiors, another for aerials, a third for twilight shots. These become child orders under a parent.

### 3. Pre-Shoot Communication
Automated reminder emails go out to both the client and the assigned photographer(s) before the shoot. The agent also ends up text messaging/emailing the Scheduler often as well, which also requires the Scheduler maintaining frequent messaging with the assigned photographer.

### 4. The Shoot
Photographer(s) go to the property and capture the media. They upload photos, videos, Matterport scans, and other files to the system.

### 5. Processing
A processing queue shows what orders need to be handled for the day, along with the files photographers have uploaded. Processors review, edit (HDR processing, color correction, sky replacement where appropriate), and upload the finished media into the system.

### 6. Release
Once all media for an order is processed and uploaded, it is "released" to the customer. The agent receives an email notification that their media is ready.

### 7. Client Access and Payment
The agent visits the client app to view their media and pay for the order.

### 8. Listing Services (Optional)
When the agent has an MLS number for their listing, they can create flyers or a virtual tour. These features automatically pull in the order's media and combine it with MLS listing data. The virtual tour becomes a public URL the agent can submit to the MLS.

## Design Principles

### Reduce Friction Above All Else

Agents don't have time to understand our system. Every screen, email, and interaction should require the minimum possible cognitive load. If an agent has to stop and think about what a button means, we've failed.

This drives specific decisions:
- Terminology must be agent-friendly, not technical. "No Disclosures Required" not "Unaltered Photos."
- Workflows should have as few steps as possible. If we can make a decision for the agent, we should.
- Error states should tell the agent what to do, not what went wrong technically.

### Speed Is the Product

"Shoot Today. Live Tomorrow" isn't a tagline — it's the core value proposition. Processing workflows, system performance, and notification timing all exist to support next-day delivery. Any feature or architectural decision that slows down the order-to-delivery pipeline needs strong justification.

### Compliance Should Be Invisible When Possible

AB 723 compliance is important but it's our problem to solve, not the agent's. When a shoot has no altered photos, the agent should never see compliance-related UI. When it does, the interface should tell them exactly what to do without requiring them to understand the law.

### Support the Full Spectrum

Not all clients need the same things. Property managers just want photos. Agents want the full suite. Legacy clients need their existing media to keep working. The system must accommodate all of these without the complexity of one workflow bleeding into another.
