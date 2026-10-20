import { z } from "zod";
import { db } from "../services/db";
import { publicUser } from "../services/messages";
import { requireCondition } from "../security/errors";
import { uuid } from "../../../../packages/contracts";
export async function visibleMoment(userId: string, id: string) {
  const m = await db.moment.findUnique({ where: { id } });
  requireCondition(m, 404, "NOT_FOUND");
  if (m.authorId !== userId) {
    requireCondition(
      m.privacy === "FRIENDS" &&
        (await db.friendship.findUnique({
          where: {
            ownerId_friendId: { ownerId: userId, friendId: m.authorId },
          },
        })),
    );
    requireCondition(
      !(await db.blockedUser.findFirst({
        where: {
          OR: [
            { ownerId: userId, targetId: m.authorId },
            { ownerId: m.authorId, targetId: userId },
          ],
        },
      })),
    );
  }
  return m;
}
export async function momentsRoute(
  userId: string,
  method: string,
  path: string[],
  body: unknown,
  url: URL,
) {
  const [, id, sub, commentId] = path;
  if (!id) {
    if (method === "GET") {
      const friends = await db.friendship.findMany({
        where: { ownerId: userId },
        select: { friendId: true },
      });
      const blocks = await db.blockedUser.findMany({
        where: { OR: [{ ownerId: userId }, { targetId: userId }] },
      });
      const blocked = new Set(blocks.flatMap((b) => [b.ownerId, b.targetId]));
      const before = url.searchParams.get("before");
      return db.moment.findMany({
        where: {
          OR: [
            { authorId: userId },
            {
              authorId: {
                in: friends
                  .map((f) => f.friendId)
                  .filter((id) => !blocked.has(id)),
              },
              privacy: "FRIENDS",
            },
          ],
          ...(before
            ? { createdAt: { lt: z.coerce.date().parse(before) } }
            : {}),
        },
        include: {
          author: { select: publicUser },
          media: { include: { media: { select: { mime: true, name: true } } } },
          likes: true,
          comments: { take: 30, orderBy: { createdAt: "asc" } },
        },
        orderBy: { createdAt: "desc" },
        take: 20,
      });
    }
    if (method === "POST") {
      const v = z
        .object({
          text: z.string().trim().max(5000),
          privacy: z.enum(["FRIENDS", "PRIVATE"]).default("FRIENDS"),
          mediaIds: z.array(uuid).max(9).default([]),
        })
        .strict()
        .parse(body);
      requireCondition(v.text.length || v.mediaIds.length, 400, "EMPTY_POST");
      const ids = [...new Set(v.mediaIds)];
      requireCondition(
        (await db.media.count({
          where: { id: { in: ids }, ownerId: userId, status: "READY",
            OR: [{ mime: { startsWith: "image/" } }, { mime: { startsWith: "video/" } }] },
        })) === ids.length,
        400,
        "INVALID_MEDIA",
      );
      return db.moment.create({
        data: {
          authorId: userId,
          text: v.text,
          privacy: v.privacy,
          media: { create: ids.map((mediaId) => ({ mediaId })) },
        },
      });
    }
    return;
  }
  const m = await visibleMoment(userId, uuid.parse(id));
  if (!sub && method === "DELETE") {
    requireCondition(m.authorId === userId);
    await db.moment.delete({ where: { id } });
    return { ok: true };
  }
  if (sub === "likes") {
    if (method === "POST")
      return db.momentLike.upsert({
        where: { momentId_userId: { momentId: id, userId } },
        create: { momentId: id, userId },
        update: {},
      });
    if (method === "DELETE") {
      await db.momentLike.deleteMany({ where: { momentId: id, userId } });
      return { ok: true };
    }
  }
  if (sub === "comments" && method === "POST") {
    const { text } = z
      .object({ text: z.string().trim().min(1).max(1000) })
      .strict()
      .parse(body);
    return db.momentComment.create({ data: { momentId: id, userId, text } });
  }
  if (sub === "comments" && commentId && method === "DELETE") {
    const result = await db.momentComment.deleteMany({
      where: { id: uuid.parse(commentId), momentId: id, userId },
    });
    requireCondition(result.count, 404, "NOT_FOUND");
    return { ok: true };
  }
}
